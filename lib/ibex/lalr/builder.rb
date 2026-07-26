# frozen_string_literal: true

require "set"

module Ibex
  module LALR
    # Builds deterministic SLR, direct LALR(1), or canonical LR(1) automata.
    # rubocop:disable Metrics/ClassLength -- collection strategies share one action/conflict construction path.
    class Builder
      AUGMENTED_PRODUCTION = -1 #: Integer

      ALGORITHMS = %i[slr lalr ielr lr1].freeze #: Array[Symbol]
      LALR_STRATEGIES = %i[direct canonical_merge].freeze #: Array[Symbol]

      # @rbs @grammar: IR::Grammar
      # @rbs @algorithm: Symbol
      # @rbs @lalr_strategy: Symbol
      # @rbs @sets: Analysis::Sets
      # @rbs @productions_by_lhs: Hash[Integer, Array[IR::Production]]
      # @rbs @resolver: ConflictResolver
      # @rbs @metrics: BuildMetrics?

      attr_reader :metrics #: BuildMetrics?

      # @rbs (IR::Grammar grammar, ?algorithm: Symbol | String, ?lalr_strategy: Symbol | String) -> void
      def initialize(grammar, algorithm: :lalr, lalr_strategy: :direct)
        unless ALGORITHMS.include?(algorithm.to_sym)
          raise ArgumentError, "unknown parser algorithm #{algorithm.inspect}"
        end
        unless LALR_STRATEGIES.include?(lalr_strategy.to_sym)
          raise ArgumentError, "unknown LALR construction strategy #{lalr_strategy.inspect}"
        end

        @grammar = grammar
        @algorithm = algorithm.to_sym
        @lalr_strategy = lalr_strategy.to_sym
        @sets = Analysis::Sets.new(grammar)
        @productions_by_lhs = grammar.productions.group_by(&:lhs)
        @resolver = ConflictResolver.new(grammar)
        @metrics = nil
      end

      # @rbs () -> IR::Automaton
      def build
        merged_items, merged_transitions, construction_states, canonical_states, strategy = automaton_collection
        states = build_states(merged_items, merged_transitions)
        states = DefaultReductions.apply(states, terminal_ids: @grammar.terminals.map(&:id))
        conflicts = states.flat_map(&:conflicts)
        shift_reduce = conflicts.select { |item| item[:type] == :shift_reduce }
        counted_shift_reduce = shift_reduce.count { |item| item.dig(:resolution, :by) == :default_shift }
        summary = { sr: counted_shift_reduce,
                    resolved_sr: shift_reduce.length - counted_shift_reduce,
                    rr: conflicts.count { |item| item[:type] == :reduce_reduce },
                    expected_sr: @grammar.expect,
                    expectation_met: counted_shift_reduce == @grammar.expect } #: IR::conflict_summary
        expected_rr = @grammar.expect_rr
        if expected_rr
          summary[:expected_rr] = expected_rr
          summary[:rr_expectation_met] = summary[:rr] == expected_rr
        end
        @metrics = BuildMetrics.new(
          construction_states: construction_states,
          canonical_states: canonical_states,
          final_states: states.length,
          strategy: strategy
        )
        IR::Automaton.new(grammar: @grammar, states: states, conflict_summary: summary,
                          algorithm: algorithm_name)
      end

      private

      # @rbs () -> [Array[packed_items], transitions, Integer, Integer?, Symbol]
      def automaton_collection
        if @algorithm == :ielr
          states, transitions = canonical_collection
          items, merged_transitions = IELRPartition.new(@grammar, states, transitions).build
          return [items, merged_transitions, states.length, states.length, :ielr_partition]
        end

        if @algorithm == :lr1
          states, transitions = canonical_collection
          return [pack_canonical_items(states), transitions, states.length, states.length, :canonical_lr1]
        end

        if @lalr_strategy == :canonical_merge
          states, transitions = canonical_collection
          items, merged_transitions = merge_lalr(states, transitions)
          apply_slr_lookaheads(items) if @algorithm == :slr
          return [items, merged_transitions, states.length, states.length, :canonical_merge]
        end

        items, transitions = DirectLookaheads.new(@grammar, @sets).build
        apply_slr_lookaheads(items) if @algorithm == :slr
        [items, transitions, items.length, nil, :direct_lalr]
      end

      # @rbs () -> String
      def algorithm_name
        { lalr: "lalr1", ielr: "ielr1" }.fetch(@algorithm, @algorithm.to_s)
      end

      # @rbs () -> [Array[item_set], transitions]
      def canonical_collection
        seed = Set[[AUGMENTED_PRODUCTION, 0, 0]] #: item_set
        states = [closure(seed)]
        transitions = [] #: transitions
        indexes = { item_key(states.first) => 0 }
        cursor = 0
        while cursor < states.length
          transitions[cursor] = {}
          next_symbols(states[cursor]).each do |symbol_id|
            target = go_to(states[cursor], symbol_id)
            key = item_key(target)
            target_id = indexes[key] ||= begin
              states << target
              states.length - 1
            end
            transitions[cursor][symbol_id] = target_id
          end
          cursor += 1
        end
        [states, transitions]
      end

      # @rbs (item_set seed) -> item_set
      def closure(seed)
        items = seed.dup
        queue = seed.to_a
        until queue.empty?
          production_id, dot, lookahead = queue.shift
          rhs = rhs_for(production_id)
          grammar_symbol = @grammar.symbol_by_id(rhs[dot])
          next unless grammar_symbol&.nonterminal?

          lookaheads = suffix_lookaheads(rhs.drop(dot + 1), lookahead)
          @productions_by_lhs.fetch(grammar_symbol.id, Array.new(0)).each do |production|
            lookaheads.each do |token_id|
              item = [production.id, 0, token_id] #: lr_item
              enqueue_item(items, queue, item)
            end
          end
        end
        items
      end

      # @rbs (Array[Integer] suffix, Integer inherited) -> Array[Integer]
      def suffix_lookaheads(suffix, inherited)
        bits = @sets.first_of_sequence(suffix)
        bits |= (1 << inherited) if @sets.sequence_nullable?(suffix)
        @grammar.terminals.filter_map { |terminal| terminal.id if bits.anybits?(1 << terminal.id) }
      end

      # @rbs (item_set items, Array[lr_item] queue, lr_item item) -> void
      def enqueue_item(items, queue, item)
        queue << item if items.add?(item)
      end

      # @rbs (item_set items) -> Array[Integer]
      def next_symbols(items)
        items.filter_map { |production_id, dot, _lookahead| rhs_for(production_id)[dot] }.uniq.sort
      end

      # @rbs (item_set items, Integer symbol_id) -> item_set
      def go_to(items, symbol_id)
        moved = items.filter_map do |production_id, dot, lookahead|
          next unless rhs_for(production_id)[dot] == symbol_id

          [production_id, dot + 1, lookahead] #: lr_item
        end
        closure(Set.new(moved))
      end

      # @rbs (Array[item_set] states, transitions transitions) -> [Array[packed_items], transitions]
      def merge_lalr(states, transitions)
        groups = {} #: Hash[Array[item_core], Integer]
        state_groups = states.map do |items|
          core = core_key(items)
          groups[core] ||= groups.length
        end
        merged = Array.new(groups.length) do
          Hash.new { |hash, key| hash[key] = Set.new } #: packed_items
        end
        states.each_with_index do |items, state_id|
          items.each { |production, dot, lookahead| merged[state_groups[state_id]][[production, dot]] << lookahead }
        end
        merged_transitions = Array.new(groups.length) do
          {} #: Hash[Integer, Integer]
        end
        transitions.each_with_index do |edges, state_id|
          edges.each { |symbol, target| merged_transitions[state_groups[state_id]][symbol] = state_groups[target] }
        end
        [merged, merged_transitions]
      end

      # @rbs (Array[item_set] states) -> Array[packed_items]
      def pack_canonical_items(states)
        states.map do |items|
          packed = Hash.new { |hash, key| hash[key] = Set.new } #: packed_items
          items.each { |production, dot, lookahead| packed[[production, dot]] << lookahead }
          packed
        end
      end

      # @rbs (Array[packed_items] states) -> void
      def apply_slr_lookaheads(states)
        states.each do |items|
          items.each do |(production_id, dot), lookaheads|
            next unless dot == rhs_for(production_id).length

            lookaheads.replace(slr_lookaheads(production_id))
          end
        end
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def slr_lookaheads(production_id)
        return [0] if production_id == AUGMENTED_PRODUCTION

        lhs = @grammar.productions.fetch(production_id).lhs
        bits = @sets.follow_bits.fetch(lhs)
        @grammar.terminals.filter_map { |terminal| terminal.id if bits.anybits?(1 << terminal.id) }
      end

      # @rbs (Array[packed_items] merged_items, transitions transitions) -> Array[IR::AutomatonState]
      def build_states(merged_items, transitions)
        merged_items.each_with_index.map do |item_map, state_id|
          items = item_map.sort.map do |(production, dot), lookaheads|
            IR::AutomatonItem.new(production: production, dot: dot, lookaheads: lookaheads.to_a)
          end
          build_state(state_id, items, transitions[state_id])
        end
      end

      # @rbs (Integer state_id, Array[IR::AutomatonItem] items, Hash[Integer, Integer] transitions) -> IR::AutomatonState
      def build_state(state_id, items, transitions)
        candidates = Hash.new { |hash, key| hash[key] = Array.new(0) } #: Hash[Integer, Array[IR::parser_action]]
        gotos = {} #: Hash[Integer, Integer]
        transitions.each do |symbol_id, target|
          grammar_symbol = @grammar.symbol_by_id(symbol_id)
          raise Ibex::Error, "missing grammar symbol id #{symbol_id}" unless grammar_symbol

          if grammar_symbol.terminal?
            candidates[symbol_id] << { type: :shift, state: target }
          else
            gotos[symbol_id] = target
          end
        end
        add_completed_actions(items, candidates)
        actions, conflicts = resolve_actions(candidates)
        IR::AutomatonState.new(id: state_id, items: items, transitions: transitions, actions: actions,
                               gotos: gotos, conflicts: conflicts)
      end

      # @rbs (Array[IR::AutomatonItem] items, Hash[Integer, Array[IR::parser_action]] candidates) -> void
      def add_completed_actions(items, candidates)
        items.each do |item|
          next unless item.dot == rhs_for(item.production).length

          item.lookaheads.each do |lookahead|
            action = if item.production == AUGMENTED_PRODUCTION
                       { type: :accept } #: IR::accept_action
                     else
                       { type: :reduce, production: item.production } #: IR::reduce_action
                     end
            candidates[lookahead] << action
          end
        end
      end

      # @rbs (Hash[Integer, Array[IR::parser_action]] candidates) ->
      #   [Hash[Integer, IR::parser_action], Array[IR::conflict]]
      def resolve_actions(candidates)
        actions = {} #: Hash[Integer, IR::parser_action]
        conflicts = [] #: Array[IR::conflict]
        candidates.keys.sort.each do |token_id|
          action, found = @resolver.resolve(token_id, candidates[token_id])
          raise Ibex::Error, "empty parser action candidates" unless action

          actions[token_id] = action
          conflicts.concat(found)
        end
        [actions, conflicts]
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        if production_id == AUGMENTED_PRODUCTION
          start = @grammar.symbol(@grammar.start) || raise(Ibex::Error, "missing start symbol")
          return [start.id]
        end

        @grammar.productions.fetch(production_id).rhs
      end

      # @rbs (item_set items) -> Array[item_core]
      def core_key(items)
        items.map do |production, dot, _lookahead|
          [production, dot] #: item_core
        end.uniq.sort
      end

      # @rbs (item_set items) -> Array[lr_item]
      def item_key(items)
        items.to_a.sort
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
