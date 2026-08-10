# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

# Dependency construction mirrors the three formal relation definitions.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

require_relative "lookahead_propagation"

module Ibex
  module LALR
    # Computes DeRemer–Pennello goto-follow sets over an LR(0) collection.
    # The three dependency closures are kept separately because IELR relies on
    # the distinction between stable (successor/internal) and predecessor
    # dependencies when a state is split.
    class GotoFollows
      # @rbs @grammar: IR::Grammar
      # @rbs @sets: Analysis::Sets
      # @rbs @states: Array[core_set]
      # @rbs @transitions: transitions
      # @rbs @kernel_cores: Array[Array[item_core]]

      attr_reader :from_state #: Array[Integer]
      attr_reader :to_state #: Array[Integer]
      attr_reader :goto_index #: Hash[[Integer, Integer], Integer]
      attr_reader :direct_reads #: Array[Integer]
      attr_reader :successor_edges #: Array[Array[Integer]]
      attr_reader :internal_edges #: Array[Array[Integer]]
      attr_reader :includes_edges #: Array[Array[Integer]]
      attr_reader :predecessors #: Array[Array[Integer]]
      attr_reader :successor_follows #: Array[Integer]
      attr_reader :always_follows #: Array[Integer]
      attr_reader :goto_follows #: Array[Integer]
      attr_reader :follow_kernel_items #: Array[Integer]
      attr_reader :kernel_cores #: Array[Array[item_core]]

      # @rbs (IR::Grammar grammar, Analysis::Sets sets, Array[core_set] states, transitions transitions,
      #   Array[Integer] start_states, ?start_names: Array[String]?) -> void
      def initialize(grammar, sets, states, transitions, start_states, start_names: nil)
        @grammar = grammar
        @sets = sets
        @states = states
        @transitions = transitions
        @start_states = start_states
        @start_names = start_names || grammar.starts
        @kernel_cores = states.map { |items| kernel_items(items) }
        build_gotos
        build_dependencies
        build_follow_sets
        @reduction_lookaheads = nil
      end

      # @rbs (Integer state_id, Integer nonterminal_id) -> Integer?
      def goto_for(state_id, nonterminal_id)
        @goto_index[[state_id, nonterminal_id]]
      end

      # @rbs () -> Array[Hash[Integer, Integer]]
      def reduction_lookaheads
        return @reduction_lookaheads if @reduction_lookaheads

        result = Array.new(@states.length) { {} }
        seeds = @start_states.each_with_index.map do |state_id, index|
          augmented = -1 - @grammar.starts.index(@start_names.fetch(index))
          [state_id, [augmented, 0], eof_id]
        end
        propagated = LookaheadPropagation.new(
          @grammar, @sets, @states, @transitions, seeds: seeds
        ).build
        @states.each_with_index do |items, state_id|
          items.each do |production_id, dot|
            next unless dot == rhs_for(production_id).length

            values = propagated.fetch(state_id).fetch([production_id, dot], [])
            result.fetch(state_id)[production_id] = values.reduce(0) do |bits, token|
              bits | (1 << token)
            end
          end
        end
        @reduction_lookaheads = result
      end

      private

      # @rbs () -> void
      def build_gotos
        @from_state = []
        @to_state = []
        @goto_symbols = []
        @goto_index = {}
        @transitions.each_with_index do |edges, state_id|
          edges.keys.sort.each do |symbol_id|
            symbol = @grammar.symbol_by_id(symbol_id)
            next unless symbol&.nonterminal?

            goto_id = @from_state.length
            @from_state << state_id
            @to_state << edges.fetch(symbol_id)
            @goto_symbols << symbol_id
            @goto_index[[state_id, symbol_id]] = goto_id
          end
        end
      end

      # @rbs () -> void
      def build_dependencies
        count = @from_state.length
        @direct_reads = Array.new(count, 0)
        @successor_edges = Array.new(count) { [] }
        @internal_edges = Array.new(count) { [] }
        @includes_edges = Array.new(count) { [] }
        @predecessors = Array.new(@states.length) { [] }
        @transitions.each_with_index do |edges, state_id|
          edges.each_value { |target| @predecessors.fetch(target) << state_id }
        end

        count.times do |goto_id|
          destination = @to_state.fetch(goto_id)
          @transitions.fetch(destination).each_key do |symbol_id|
            symbol = @grammar.symbol_by_id(symbol_id)
            if symbol&.terminal?
              @direct_reads[goto_id] |= 1 << symbol_id
            elsif symbol&.nonterminal? && @sets.nullable?(symbol_id)
              successor = @goto_index.fetch([destination, symbol_id])
              @successor_edges.fetch(goto_id) << successor
            end
          end
        end

        @start_states.each_with_index do |state_id, index|
          start_name = @start_names.fetch(index)
          start_symbol = @grammar.symbol(start_name) || raise(Ibex::Error, "missing start symbol #{start_name}")
          goto_id = @goto_index[[state_id, start_symbol.id]]
          @direct_reads[goto_id] |= 1 << eof_id if goto_id
        end

        @goto_index.each do |(inner_source, inner_symbol), inner_goto_id|
          @grammar.productions.each do |production|
            production.rhs.each_with_index do |symbol_id, position|
              next unless symbol_id == inner_symbol
              next unless @grammar.symbol_by_id(symbol_id)&.nonterminal?

              suffix = production.rhs[(position + 1)..] || []
              next unless @sets.sequence_nullable?(suffix)

              @goto_index.each do |(outer_source, outer_symbol), outer_goto_id|
                next unless outer_symbol == production.lhs

                reached = advance(outer_source, production.rhs.take(position))
                next unless reached == inner_source

                @includes_edges.fetch(inner_goto_id) << outer_goto_id
                @internal_edges.fetch(inner_goto_id) << outer_goto_id if position.zero?
              end
            end
          end
        end
        @successor_edges.each(&:uniq!)
        @internal_edges.each(&:uniq!)
        @includes_edges.each(&:uniq!)
        @predecessors.each(&:uniq!)
      end

      # @rbs () -> void
      def build_follow_sets
        @successor_follows = Analysis::Digraph.closure(@direct_reads, @successor_edges)
        internal_initial = @from_state.each_index.map do |goto_id|
          1 << symbol_for_goto(goto_id)
        end
        @internal_reachable_symbols = Analysis::Digraph.closure(internal_initial, @internal_edges)
        @always_follows = Analysis::Digraph.closure(@direct_reads, merged_edges(@successor_edges, @internal_edges))
        @goto_follows = Analysis::Digraph.closure(@always_follows, @includes_edges)
        @follow_kernel_items = @from_state.each_index.map { |goto_id| compute_follow_kernel_items(goto_id) }
      end

      # @rbs (Array[Array[Integer]], Array[Array[Integer]]) -> Array[Array[Integer]]
      def merged_edges(left, right)
        left.each_index.map { |index| (left.fetch(index) + right.fetch(index)).uniq }
      end

      # @rbs (Integer goto_id) -> Integer
      def compute_follow_kernel_items(goto_id)
        state_id = @from_state.fetch(goto_id)
        reachable = @internal_reachable_symbols.fetch(goto_id)
        @kernel_cores.fetch(state_id).each_with_index.reduce(0) do |mask, ((production_id, dot), index)|
          rhs = rhs_for(production_id)
          symbol_id = rhs[dot]
          next mask unless symbol_id && reachable.anybits?(1 << symbol_id)
          next mask unless @sets.sequence_nullable?(rhs[(dot + 1)..] || [])

          mask | (1 << index)
        end
      end

      # @rbs (core_set items) -> Array[item_core]
      def kernel_items(items)
        items.select { |production_id, dot| production_id.negative? || dot.positive? }.to_a.sort
      end

      # @rbs (Integer goto_id) -> Integer
      def symbol_for_goto(goto_id)
        @goto_symbols.fetch(goto_id)
      end

      # @rbs (Integer state_id, Array[Integer]) -> Integer?
      def advance(state_id, symbols)
        symbols.reduce(state_id) do |current, symbol_id|
          @transitions.fetch(current).fetch(symbol_id, nil) || break
        end
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        return [@grammar.symbol(@grammar.starts.fetch(-production_id - 1)).id] if production_id.negative?

        @grammar.productions.fetch(production_id).rhs
      end

      # @rbs () -> Integer
      def eof_id
        0
      end
    end
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
# steep:ignore:end
