# frozen_string_literal: true
# rbs_inline: enabled

require "set"

module Ibex
  module LALR
    # Builds an LR(0) collection and propagates LALR(1) lookaheads directly
    # over item occurrences. Canonical LR(1) states are never materialized.
    class DirectLookaheads
      AUGMENTED_PRODUCTION = -1 #: Integer
      EMPTY_PRODUCTIONS = Array.new(0).freeze #: Array[IR::Production]
      EMPTY_NODES = Array.new(0).freeze #: Array[lookahead_node]
      private_constant :EMPTY_PRODUCTIONS, :EMPTY_NODES

      # @rbs @grammar: IR::Grammar
      # @rbs @sets: Analysis::Sets
      # @rbs @productions_by_lhs: Hash[Integer, Array[IR::Production]]
      # @rbs @augmented_rhs: Array[Integer]
      # @rbs @production_rhs: Array[Array[Integer]]
      # @rbs @initial_item_cores: Array[item_core]
      # @rbs @terminal_ids: Array[Integer]
      # @rbs @terminal_masks: Array[Integer]

      # @rbs (IR::Grammar grammar, Analysis::Sets sets) -> void
      def initialize(grammar, sets)
        @grammar = grammar
        @sets = sets
        @productions_by_lhs = grammar.productions.group_by(&:lhs)
        start = grammar.symbol(grammar.start) || raise(Ibex::Error, "missing start symbol")
        @augmented_rhs = [start.id].freeze
        @production_rhs = grammar.productions.map(&:rhs).freeze
        @initial_item_cores = grammar.productions.map { |production| [production.id, 0].freeze }.freeze
        @terminal_ids = grammar.terminals.map(&:id).freeze
        @terminal_masks = @terminal_ids.map { |id| 1 << id }.freeze
      end

      # @rbs () -> [Array[packed_items], transitions]
      def build
        states, transitions = lr0_collection
        lookaheads = empty_lookaheads(states)
        propagation = propagation_graph(states, transitions, lookaheads)
        lookaheads.fetch(0).fetch([AUGMENTED_PRODUCTION, 0]) << 0
        propagate(lookaheads, propagation)
        [lookaheads, transitions]
      end

      private

      # @rbs () -> [Array[core_set], transitions]
      def lr0_collection
        seed = Set[[AUGMENTED_PRODUCTION, 0]] #: core_set
        states = [closure(seed)]
        transitions = [] #: transitions
        indexes = { item_key(states.first) => 0 }
        cursor = 0
        while cursor < states.length
          transitions[cursor] = {}
          next_symbols(states.fetch(cursor)).each do |symbol_id|
            target = go_to(states.fetch(cursor), symbol_id)
            key = item_key(target)
            target_id = indexes[key] ||= begin
              states << target
              states.length - 1
            end
            transitions.fetch(cursor)[symbol_id] = target_id
          end
          cursor += 1
        end
        [states, transitions]
      end

      # @rbs (core_set seed) -> core_set
      def closure(seed)
        items = seed.dup
        queue = seed.to_a
        cursor = 0
        while cursor < queue.length
          production_id, dot = queue.fetch(cursor)
          cursor += 1
          symbol = @grammar.symbol_by_id(rhs_for(production_id)[dot])
          next unless symbol&.nonterminal?

          @productions_by_lhs.fetch(symbol.id, EMPTY_PRODUCTIONS).each do |production|
            item = @initial_item_cores.fetch(production.id)
            queue << item if items.add?(item)
          end
        end
        items
      end

      # @rbs (core_set items) -> Array[Integer]
      def next_symbols(items)
        items.filter_map { |production_id, dot| rhs_for(production_id)[dot] }.uniq.sort
      end

      # @rbs (core_set items, Integer symbol_id) -> core_set
      def go_to(items, symbol_id)
        moved = items.filter_map do |production_id, dot|
          next unless rhs_for(production_id)[dot] == symbol_id

          [production_id, dot + 1] #: item_core
        end
        closure(Set.new(moved))
      end

      # @rbs (Array[core_set] states) -> Array[packed_items]
      def empty_lookaheads(states)
        states.map do |items|
          items.to_h { |item| [item, Set.new] } #: packed_items
        end
      end

      # @rbs (Array[core_set] states, transitions transitions, Array[packed_items] lookaheads) ->
      #   Hash[lookahead_node, Array[lookahead_node]]
      def propagation_graph(states, transitions, lookaheads)
        edges = Hash.new { |hash, key| hash[key] = [] } #: Hash[lookahead_node, Array[lookahead_node]]
        states.each_with_index do |items, state_id|
          items.each do |production_id, dot|
            add_transition_edge(edges, transitions, state_id, production_id, dot)
            add_closure_relations(edges, lookaheads, state_id, production_id, dot)
          end
        end
        edges.each_value(&:uniq!)
        edges
      end

      # @rbs (Hash[lookahead_node, Array[lookahead_node]] edges, transitions transitions,
      #   Integer state_id, Integer production_id, Integer dot) -> void
      def add_transition_edge(edges, transitions, state_id, production_id, dot)
        symbol_id = rhs_for(production_id)[dot]
        return unless symbol_id

        target_state = transitions.fetch(state_id).fetch(symbol_id)
        source = [state_id, production_id, dot] #: lookahead_node
        target = [target_state, production_id, dot + 1] #: lookahead_node
        edges[source] << target
      end

      # @rbs (Hash[lookahead_node, Array[lookahead_node]] edges, Array[packed_items] lookaheads,
      #   Integer state_id, Integer production_id, Integer dot) -> void
      def add_closure_relations(edges, lookaheads, state_id, production_id, dot)
        rhs = rhs_for(production_id)
        symbol = @grammar.symbol_by_id(rhs[dot])
        return unless symbol&.nonterminal?

        suffix = rhs.drop(dot + 1)
        spontaneous = terminal_ids(@sets.first_of_sequence(suffix))
        source = [state_id, production_id, dot] #: lookahead_node
        @productions_by_lhs.fetch(symbol.id, EMPTY_PRODUCTIONS).each do |production|
          target_item = @initial_item_cores.fetch(production.id)
          lookaheads.fetch(state_id).fetch(target_item).merge(spontaneous)
          if @sets.sequence_nullable?(suffix)
            target = [state_id, production.id, 0] #: lookahead_node
            edges[source] << target
          end
        end
      end

      # @rbs (Array[packed_items] lookaheads, Hash[lookahead_node, Array[lookahead_node]] edges) -> void
      def propagate(lookaheads, edges)
        queue = lookaheads.each_with_index.flat_map do |items, state_id|
          items.filter_map do |(production_id, dot), tokens|
            next if tokens.empty?

            [state_id, production_id, dot] #: lookahead_node
          end
        end #: Array[lookahead_node]
        queued = queue.to_h { |node| [node, true] } #: Hash[lookahead_node, bool]
        cursor = 0
        while cursor < queue.length
          source = queue.fetch(cursor)
          cursor += 1
          queued.delete(source)
          source_set = node_set(lookaheads, source)
          edges.fetch(source, EMPTY_NODES).each do |target|
            target_set = node_set(lookaheads, target)
            previous_size = target_set.size
            target_set.merge(source_set)
            next if target_set.size == previous_size || queued[target]

            queue << target
            queued[target] = true
          end
        end
      end

      # @rbs (Array[packed_items] lookaheads, lookahead_node node) -> Set[Integer]
      def node_set(lookaheads, node)
        state_id, production_id, dot = node
        lookaheads.fetch(state_id).fetch([production_id, dot])
      end

      # @rbs (Integer bits) -> Array[Integer]
      def terminal_ids(bits)
        selected = [] #: Array[Integer]
        index = 0
        while index < @terminal_ids.length
          selected << @terminal_ids[index] if bits.anybits?(@terminal_masks[index])
          index += 1
        end
        selected
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        return @augmented_rhs if production_id == AUGMENTED_PRODUCTION

        @production_rhs.fetch(production_id)
      end

      # @rbs (core_set items) -> Array[item_core]
      def item_key(items)
        items.to_a.sort
      end
    end
  end
end
