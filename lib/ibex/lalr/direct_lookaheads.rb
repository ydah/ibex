# frozen_string_literal: true
# rbs_inline: enabled

require "set"

# This class intentionally owns collection and propagation state so the
# single-start compatibility path remains byte-identical.
# rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

module Ibex
  module LALR
    # Builds an LR(0) collection and propagates LALR(1) lookaheads directly
    # over item occurrences. Canonical LR(1) states are never materialized.
    class DirectLookaheads
      AUGMENTED_PRODUCTION = -1 #: Integer
      EMPTY_PRODUCTIONS = Array.new(0).freeze #: Array[IR::Production]
      EMPTY_NODES = Array.new(0).freeze #: Array[Integer]
      private_constant :EMPTY_PRODUCTIONS, :EMPTY_NODES

      attr_reader :lr0_state_count #: Integer?
      attr_reader :lr0_item_count #: Integer?
      attr_reader :propagation_edge_count #: Integer?
      attr_reader :states #: Array[core_set]
      attr_reader :transitions #: transitions

      # @rbs (IR::Grammar grammar, Analysis::Sets sets, ?starts: Array[String]?, ?profile: bool) -> void
      def initialize(grammar, sets, starts: nil, profile: false)
        @grammar = grammar
        @sets = sets
        @starts = (starts || grammar.starts).dup
        raise ArgumentError, "starts must be a nonempty subset of grammar starts" if
          @starts.empty? || (@starts - grammar.starts).any?

        @productions_by_lhs = grammar.productions.group_by(&:lhs)
        @augmented_production_ids = @starts.map { |name| AUGMENTED_PRODUCTION - start_index(name) }
        @augmented_rhs = @starts.each_with_index.to_h do |name, index|
          symbol = grammar.symbol(name) || raise(Ibex::Error, "missing start symbol #{name}")
          [@augmented_production_ids.fetch(index), [symbol.id].freeze]
        end.freeze
        @production_rhs = grammar.productions.map(&:rhs).freeze
        @augmented_item_cores = @augmented_rhs.to_h do |production_id, rhs|
          [production_id, item_cores_for(production_id, rhs.length)]
        end.freeze
        @production_item_cores = grammar.productions.map do |production|
          item_cores_for(production.id, production.rhs.length)
        end.freeze
        initialize_item_encoding
        @terminal_ids = grammar.terminals.map(&:id).freeze
        @terminal_masks = @terminal_ids.map { |id| 1 << id }.freeze
        @terminal_ids_by_bits = {} #: Hash[Integer, Array[Integer]]
        @lr0_state_count = nil
        @lr0_item_count = nil
        @propagation_edge_count = nil
        @profile = profile
      end

      # @rbs () -> [Array[packed_items], transitions]
      def build
        states, transitions = lr0_collection
        @states = states
        @transitions = transitions
        lookaheads = empty_lookaheads(states)
        propagation = propagation_graph(states, transitions, lookaheads)
        if @profile
          @lr0_state_count = states.length
          @lr0_item_count = states.sum(&:length)
          @propagation_edge_count = propagation.values.sum(&:length)
        end
        @starts.each_with_index do |_name, index|
          lookaheads.fetch(index).fetch(item_core(augmented_production(index), 0)) << 0
        end
        propagate(lookaheads, propagation)
        [lookaheads, transitions]
      end

      # @rbs (Integer index) -> Integer
      def augmented_production(index)
        @augmented_production_ids.fetch(index)
      end

      private

      # @rbs () -> void
      def initialize_item_encoding
        @item_key_stride = [*@augmented_rhs.values, *@production_rhs].map(&:length).max.to_i + 1
        # Negative augmented ids are global to Grammar#starts.  A builder
        # may isolate a non-first entry, so reserve the full global range.
        @production_offset = @grammar.starts.length
        @node_stride = (@production_offset + @production_rhs.length) * @item_key_stride
      end

      # @rbs () -> [Array[core_set], transitions]
      def lr0_collection
        states = @starts.each_index.map { |index| closure(Set[item_core(augmented_production(index), 0)]) }
        transitions = [] #: transitions
        indexes = {} #: Hash[Array[Integer], Integer]
        states.each_with_index { |items, index| indexes[item_key(items)] = index }
        cursor = 0
        while cursor < states.length
          transitions[cursor] = {}
          shifted_kernels(states.fetch(cursor)).keys.sort.each do |symbol_id|
            target = closure(shifted_kernels(states.fetch(cursor)).fetch(symbol_id))
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
        states.map { |items| items.to_h { |item| [item, Set.new] } }
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
        edges[node_id(state_id, production_id, dot)] << node_id(target_state, production_id, dot + 1)
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
          edges[source] << node_id(state_id, production.id, 0) if @sets.sequence_nullable?(suffix)
        end
      end

      # @rbs (Array[packed_items] lookaheads, Hash[Integer, Array[Integer]] edges) -> void
      def propagate(lookaheads, edges)
        queue = lookaheads.each_with_index.flat_map do |items, state_id|
          items.filter_map do |(production_id, dot), tokens|
            node_id(state_id, production_id, dot) unless tokens.empty?
          end
        end
        queued = queue.to_h { |node| [node, true] }
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
        production_id = ((item / @item_key_stride) - @production_offset).to_i
        dot = (item % @item_key_stride).to_i
        lookaheads.fetch(state_id).fetch(item_core(production_id, dot))
      end

      # @rbs (Integer state_id, Integer production_id, Integer dot) -> Integer
      def node_id(state_id, production_id, dot)
        ((state_id * @node_stride) + ((production_id + @production_offset) * @item_key_stride) + dot).to_i
      end

      # @rbs (Integer bits) -> Array[Integer]
      def terminal_ids(bits)
        @terminal_ids_by_bits.fetch(bits) do
          selected = @terminal_ids.select { |id| bits.anybits?(@terminal_masks[@terminal_ids.index(id)]) }
          @terminal_ids_by_bits[bits] = selected.freeze
        end
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        return @augmented_rhs.fetch(production_id) if production_id.negative?

        @production_rhs.fetch(production_id)
      end

      # @rbs (Integer production_id, Integer rhs_length) -> Array[item_core]
      def item_cores_for(production_id, rhs_length)
        result = Array.new(rhs_length + 1) #: Array[item_core]
        rhs_length.next.times do |dot|
          core = [production_id, dot].freeze #: item_core
          result[dot] = core
        end
        result.freeze
      end

      # @rbs (Integer production_id, Integer dot) -> item_core
      def item_core(production_id, dot)
        raise IndexError, "invalid item dot: #{dot}" if dot.negative?
        return @augmented_item_cores.fetch(production_id).fetch(dot) if production_id.negative?

        @production_item_cores.fetch(production_id).fetch(dot)
      end

      # @rbs (core_set items) -> Array[Integer]
      def item_key(items)
        items.map do |production_id, dot|
          (((production_id + @production_offset) * @item_key_stride) + dot).to_i
        end.sort!
      end

      # @rbs (String name) -> Integer
      def start_index(name)
        @grammar.starts.index(name) || raise(Ibex::Error, "missing start symbol #{name}")
      end
    end
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
