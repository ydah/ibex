# frozen_string_literal: true
# rbs_inline: enabled

require "set"

module Ibex
  module Verify
    # Independently derives canonical LR(1) and LR(0) item collections.
    class ReferenceCollection
      # Immutable canonical collection and its symbol transitions.
      class Collection
        attr_reader :states #: Array[Set[Array[Integer]]]
        attr_reader :transitions #: Array[Hash[Integer, Integer]]

        # @rbs (states: Array[Set[Array[Integer]]], transitions: Array[Hash[Integer, Integer]]) -> void
        def initialize(states:, transitions:)
          @states = states
          @transitions = transitions
          freeze
        end
      end

      # @rbs (IR::Grammar grammar, ?max_states: Integer, ?max_items: Integer) -> void
      def initialize(grammar, max_states: 100_000, max_items: 1_000_000)
        raise ArgumentError, "max_states must be positive" unless max_states.positive?
        raise ArgumentError, "max_items must be positive" unless max_items.positive?

        @grammar = grammar
        @max_states = max_states
        @max_items = max_items
        @sets = Analysis::Sets.new(grammar)
        @productions = grammar.productions.group_by(&:lhs)
        @item_count = 0
      end

      # @rbs (Symbol kind) -> Collection
      def build(kind)
        raise ArgumentError, "kind must be :lr0 or :lr1" unless %i[lr0 lr1].include?(kind)

        @item_count = 0
        seeds = @grammar.starts.map.with_index do |name, index|
          raise Ibex::Error, "(verify):1:1: missing start symbol #{name}" unless @grammar.symbol(name)

          item = kind == :lr1 ? [-index - 1, 0, eof_id] : [-index - 1, 0]
          account_item
          closure(Set[item], kind)
        end
        collection(seeds, kind)
      end

      private

      # @rbs (Array[Set[Array[Integer]]] seeds, Symbol kind) -> Collection
      def collection(seeds, kind)
        states = [] #: Array[Set[Array[Integer]]]
        transitions = [] #: Array[Hash[Integer, Integer]]
        indexes = {} #: Hash[Array[Array[Integer]], Integer]
        seeds.each { |seed| insert_state(states, indexes, seed) }
        cursor = 0
        while cursor < states.length
          transitions[cursor] = {}
          next_symbols(states.fetch(cursor)).each do |symbol_id|
            target = go_to(states.fetch(cursor), symbol_id, kind)
            target_id = insert_state(states, indexes, target)
            transitions.fetch(cursor)[symbol_id] = target_id
          end
          cursor += 1
        end
        Collection.new(states: states.freeze, transitions: transitions.freeze).freeze
      end

      # @rbs (Array[Set[Array[Integer]]] states, Hash[Array[Array[Integer]], Integer] indexes,
      #   Set[Array[Integer]] state) -> Integer
      def insert_state(states, indexes, state)
        key = state.to_a.sort
        existing = indexes[key]
        return existing if existing
        if states.length >= @max_states
          raise BudgetExceeded.new(
            "(verify):1:1: reference collection exceeds #{@max_states} states", bounds: bounds
          )
        end

        states << state.freeze
        indexes[key] = states.length - 1
      end

      # @rbs (Set[Array[Integer]] seed, Symbol kind) -> Set[Array[Integer]]
      def closure(seed, kind)
        items = seed.dup
        queue = seed.to_a
        cursor = 0
        while cursor < queue.length
          item = queue.fetch(cursor)
          cursor += 1
          production_id = item.fetch(0)
          dot = item.fetch(1)
          lookahead = item[2]
          symbol_id = rhs_for(production_id)[dot]
          symbol = @grammar.symbol_by_id(symbol_id)
          next unless symbol&.nonterminal?

          productions = @productions.fetch(symbol.id) do
            [] #: Array[IR::Production]
          end
          productions.each do |production|
            if kind == :lr1
              closure_lookaheads(production_id, dot, lookahead).each do |token|
                add_item(items, queue, [production.id, 0, token])
              end
            else
              add_item(items, queue, [production.id, 0])
            end
          end
        end
        items
      end

      # @rbs (Set[Array[Integer]] state, Integer symbol_id, Symbol kind) -> Set[Array[Integer]]
      def go_to(state, symbol_id, kind)
        moved = state.each_with_object(Set.new) do |item, result|
          production_id = item.fetch(0)
          dot = item.fetch(1)
          lookahead = item[2]
          next unless rhs_for(production_id)[dot] == symbol_id

          result << (kind == :lr1 ? [production_id, dot + 1, lookahead] : [production_id, dot + 1])
        end
        closure(moved, kind)
      end

      # @rbs (Set[Array[Integer]] items, Array[Array[Integer]] queue, Array[Integer] item) -> void
      def add_item(items, queue, item)
        return if items.include?(item)

        account_item
        items << item
        queue << item
      end

      # @rbs () -> void
      def account_item
        if @item_count >= @max_items
          raise BudgetExceeded.new(
            "(verify):1:1: reference collection exceeds #{@max_items} items", bounds: bounds
          )
        end

        @item_count += 1
      end

      # @rbs (Set[Array[Integer]] state) -> Array[Integer]
      def next_symbols(state)
        state.filter_map { |item| rhs_for(item.fetch(0))[item.fetch(1)] }.uniq.sort
      end

      # @rbs (Integer production_id, Integer dot, Integer? inherited) -> Array[Integer]
      def closure_lookaheads(production_id, dot, inherited)
        suffix = rhs_for(production_id).drop(dot + 1)
        bits = @sets.first_of_sequence(suffix)
        bits |= (1 << inherited) if inherited && @sets.sequence_nullable?(suffix)
        @grammar.terminals.filter_map { |terminal| terminal.id if bits.anybits?(1 << terminal.id) }
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        return [start_symbol(production_id).id] if production_id.negative?

        @grammar.productions.fetch(production_id).rhs
      end

      # @rbs (Integer production_id) -> IR::GrammarSymbol
      def start_symbol(production_id)
        name = @grammar.starts.fetch(-production_id - 1)
        @grammar.symbol(name) || raise(Ibex::Error, "(verify):1:1: missing start symbol #{name}")
      end

      # @rbs () -> Integer
      def eof_id
        symbol = @grammar.symbol("$eof")
        symbol&.id || raise(Ibex::Error, "(verify):1:1: grammar has no $eof terminal")
      end

      # @rbs () -> Hash[Symbol, Integer]
      def bounds
        { max_states: @max_states, max_items: @max_items }
      end
    end
  end
end
