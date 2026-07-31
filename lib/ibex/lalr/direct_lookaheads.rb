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
      EMPTY_NODES = Array.new(0).freeze #: Array[Integer]
      private_constant :EMPTY_PRODUCTIONS, :EMPTY_NODES

      # @rbs @grammar: IR::Grammar
      # @rbs @sets: Analysis::Sets
      # @rbs @productions_by_lhs: Hash[Integer, Array[IR::Production]]
      # @rbs @augmented_rhs: Array[Integer]
      # @rbs @production_rhs: Array[Array[Integer]]
      # @rbs @augmented_item_cores: Array[item_core]
      # @rbs @production_item_cores: Array[Array[item_core]]
      # @rbs @item_key_stride: Integer
      # @rbs @node_stride: Integer
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
        @augmented_item_cores = item_cores_for(AUGMENTED_PRODUCTION, @augmented_rhs.length)
        @production_item_cores = grammar.productions.map do |production|
          item_cores_for(production.id, production.rhs.length)
        end.freeze
        initialize_item_encoding(grammar.productions.length)
        @terminal_ids = grammar.terminals.map(&:id).freeze
        @terminal_masks = @terminal_ids.map { |id| 1 << id }.freeze
      end

      # @rbs () -> [Array[packed_items], transitions]
      def build
        states, transitions = lr0_collection
        lookaheads = empty_lookaheads(states)
        propagation = propagation_graph(states, transitions, lookaheads)
        lookaheads.fetch(0).fetch(item_core(AUGMENTED_PRODUCTION, 0)) << 0
        propagate(lookaheads, propagation)
        [lookaheads, transitions]
      end

      private

      # @rbs (Integer production_count) -> void
      def initialize_item_encoding(production_count)
        @item_key_stride = [@augmented_rhs, *@production_rhs].map(&:length).max.to_i + 1
        @node_stride = (production_count + 1) * @item_key_stride
      end

      # @rbs () -> [Array[core_set], transitions]
      def lr0_collection
        seed = Set[item_core(AUGMENTED_PRODUCTION, 0)] #: core_set
        states = [closure(seed)]
        transitions = [] #: transitions
        indexes = { item_key(states.first) => 0 }
        cursor = 0
        while cursor < states.length
          transitions[cursor] = {}
          kernels = shifted_kernels(states.fetch(cursor))
          kernels.keys.sort.each do |symbol_id|
            target = closure(kernels.fetch(symbol_id))
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
            item = item_core(production.id, 0)
            queue << item if items.add?(item)
          end
        end
        items
      end

      # @rbs (core_set items) -> Hash[Integer, core_set]
      def shifted_kernels(items)
        kernels = {} #: Hash[Integer, core_set]
        items.each do |production_id, dot|
          symbol_id = rhs_for(production_id)[dot]
          next unless symbol_id

          (kernels[symbol_id] ||= Set.new) << item_core(production_id, dot + 1)
        end
        kernels
      end

      # @rbs (Array[core_set] states) -> Array[packed_items]
      def empty_lookaheads(states)
        states.map do |items|
          items.to_h { |item| [item, Set.new] } #: packed_items
        end
      end

      # @rbs (Array[core_set] states, transitions transitions, Array[packed_items] lookaheads) ->
      #   Hash[Integer, Array[Integer]]
      def propagation_graph(states, transitions, lookaheads)
        edges = Hash.new { |hash, key| hash[key] = [] } #: Hash[Integer, Array[Integer]]
        states.each_with_index do |items, state_id|
          items.each do |production_id, dot|
            add_transition_edge(edges, transitions, state_id, production_id, dot)
            add_closure_relations(edges, lookaheads, state_id, production_id, dot)
          end
        end
        edges.each_value(&:uniq!)
        edges
      end

      # @rbs (Hash[Integer, Array[Integer]] edges, transitions transitions,
      #   Integer state_id, Integer production_id, Integer dot) -> void
      def add_transition_edge(edges, transitions, state_id, production_id, dot)
        symbol_id = rhs_for(production_id)[dot]
        return unless symbol_id

        target_state = transitions.fetch(state_id).fetch(symbol_id)
        source = node_id(state_id, production_id, dot)
        target = node_id(target_state, production_id, dot + 1)
        edges[source] << target
      end

      # @rbs (Hash[Integer, Array[Integer]] edges, Array[packed_items] lookaheads,
      #   Integer state_id, Integer production_id, Integer dot) -> void
      def add_closure_relations(edges, lookaheads, state_id, production_id, dot)
        rhs = rhs_for(production_id)
        symbol = @grammar.symbol_by_id(rhs[dot])
        return unless symbol&.nonterminal?

        suffix = rhs.drop(dot + 1)
        spontaneous = terminal_ids(@sets.first_of_sequence(suffix))
        source = node_id(state_id, production_id, dot)
        @productions_by_lhs.fetch(symbol.id, EMPTY_PRODUCTIONS).each do |production|
          target_item = item_core(production.id, 0)
          lookaheads.fetch(state_id).fetch(target_item).merge(spontaneous)
          if @sets.sequence_nullable?(suffix)
            target = node_id(state_id, production.id, 0)
            edges[source] << target
          end
        end
      end

      # @rbs (Array[packed_items] lookaheads, Hash[Integer, Array[Integer]] edges) -> void
      def propagate(lookaheads, edges)
        queue = lookaheads.each_with_index.flat_map do |items, state_id|
          items.filter_map do |(production_id, dot), tokens|
            next if tokens.empty?

            node_id(state_id, production_id, dot)
          end
        end #: Array[Integer]
        queued = queue.to_h { |node| [node, true] } #: Hash[Integer, bool]
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

      # @rbs (Array[packed_items] lookaheads, Integer node) -> Set[Integer]
      def node_set(lookaheads, node)
        state_id = node / @node_stride
        item = node % @node_stride
        production_id = (item / @item_key_stride) - 1
        dot = item % @item_key_stride
        lookaheads.fetch(state_id).fetch(item_core(production_id, dot))
      end

      # @rbs (Integer state_id, Integer production_id, Integer dot) -> Integer
      def node_id(state_id, production_id, dot)
        (state_id * @node_stride) + ((production_id + 1) * @item_key_stride) + dot
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

      # @rbs (Integer production_id, Integer rhs_length) -> Array[item_core]
      def item_cores_for(production_id, rhs_length)
        Array.new(rhs_length + 1) do |dot|
          [production_id, dot].freeze #: item_core
        end.freeze
      end

      # @rbs (Integer production_id, Integer dot) -> item_core
      def item_core(production_id, dot)
        raise IndexError, "invalid item dot: #{dot}" if dot.negative?
        return @augmented_item_cores.fetch(dot) if production_id == AUGMENTED_PRODUCTION
        raise IndexError, "invalid production id: #{production_id}" if production_id.negative?

        @production_item_cores.fetch(production_id).fetch(dot)
      end

      # Encode each pair collision-free before sorting so Hash does not
      # repeatedly hash and compare nested item-core arrays.
      # @rbs (core_set items) -> Array[Integer]
      def item_key(items)
        items.map do |production_id, dot|
          ((production_id + 1) * @item_key_stride) + dot
        end.sort!
      end
    end
  end
end
