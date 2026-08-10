# frozen_string_literal: true
# rbs_inline: enabled

require "set"
require_relative "../lalr/conflict"
require_relative "../lalr/default_reductions"
require_relative "../lalr/on_error_reductions"

module Ibex
  module Verify
    # @rbs! type witness_status = :accepted | :error | :missing_entry | :shifted

    # Compares canonical and submitted parser acceptance over a bounded set of
    # terminal sequences.  This is a semantic witness, not a proof of language
    # equivalence: the reference collection is complete within its budgets and
    # the token enumeration is deliberately finite.
    class LanguageWitness
      class Difference
        attr_reader :entry #: String
        attr_reader :tokens #: Array[String]
        attr_reader :canonical #: witness_status
        attr_reader :target #: witness_status

        # @rbs (entry: String, tokens: Array[String], canonical: witness_status,
        #   target: witness_status) -> void
        def initialize(entry:, tokens:, canonical:, target:)
          @entry = entry.freeze
          @tokens = tokens.dup.freeze
          @canonical = canonical
          @target = target
          freeze
        end
      end

      class Result
        attr_reader :differences #: Array[Difference]
        attr_reader :explored #: Integer
        attr_reader :truncated #: bool
        attr_reader :max_tokens #: Integer
        attr_reader :max_cases #: Integer

        # @rbs (differences: Array[Difference], explored: Integer, truncated: bool,
        #   max_tokens: Integer, max_cases: Integer) -> void
        def initialize(differences:, explored:, truncated:, max_tokens:, max_cases:)
          @differences = differences.dup.freeze
          @explored = explored
          @truncated = truncated
          @max_tokens = max_tokens
          @max_cases = max_cases
          freeze
        end

        # @rbs () -> bool
        def ok?
          differences.empty? && !truncated
        end
      end

      # @rbs (IR::Grammar grammar, IR::Automaton target, ?max_tokens: Integer,
      #   ?max_cases: Integer, ?max_states: Integer, ?max_items: Integer) -> void
      def initialize(grammar, target, max_tokens: 6, max_cases: 10_000, max_states: 100_000,
                     max_items: 1_000_000)
        raise ArgumentError, "max_tokens must be nonnegative" if max_tokens.negative?
        raise ArgumentError, "max_cases must be positive" unless max_cases.positive?

        @grammar = grammar
        @target = target
        @max_tokens = max_tokens
        @max_cases = max_cases
        @canonical = CanonicalMachine.new(
          grammar, max_states: max_states, max_items: max_items
        )
      end

      # @rbs () -> Result
      def verify
        differences = [] #: Array[Difference]
        explored = 0
        truncated = false
        token_ids = input_tokens.map(&:id)

        @grammar.starts.each do |entry|
          explored, truncated = verify_entry(entry, token_ids, differences, explored)
          break if truncated
        end

        Result.new(
          differences: differences.freeze, explored: explored, truncated: truncated,
          max_tokens: @max_tokens, max_cases: @max_cases
        )
      end

      private

      # @rbs () -> Array[IR::GrammarSymbol]
      def input_tokens
        @grammar.terminals.reject { |terminal| ["$eof", "error"].include?(terminal.name) }
      end

      # @rbs (String, Array[Integer], Array[Difference], Integer) -> [Integer, bool]
      def verify_entry(entry, token_ids, differences, explored)
        queue = [[]] #: Array[Array[Integer]]
        until queue.empty?
          tokens = queue.shift
          return [explored, true] if explored >= @max_cases

          explored += 1
          canonical = @canonical.simulate(entry, tokens)
          target = simulate_target(entry, tokens)
          if canonical != target
            differences << Difference.new(
              entry: entry, tokens: tokens.map { |id| token_name(id) },
              canonical: canonical, target: target
            )
            return [explored, false]
          end

          # Keep the worklist breadth-first so a reported witness is as short
          # as possible for each entry.
          queue.concat(token_ids.map { |token_id| tokens + [token_id] }) if
            tokens.length < @max_tokens
        end
        [explored, false]
      end

      # @rbs (Integer id) -> String
      def token_name(id)
        @grammar.symbol_by_id(id)&.name || raise(Ibex::Error, "missing terminal #{id}")
      end

      # @rbs (String entry, Array[Integer]) -> witness_status
      def simulate_target(entry, tokens)
        initial = @target.entry_states[entry]
        return :missing_entry unless initial

        machine = Machine.new(@target.states, @grammar)
        machine.simulate(initial, tokens)
      end

      # Canonical collection is intentionally built here rather than through
      # the production construction entry point, keeping this witness
      # independent from construction code.
      class CanonicalMachine
        # @rbs (IR::Grammar grammar, max_states: Integer, max_items: Integer) -> void
        def initialize(grammar, max_states:, max_items:)
          collection = ReferenceCollection.new(
            grammar, max_states: max_states, max_items: max_items
          ).build(:lr1)
          @grammar = grammar
          @states = build_states(collection)
          @entry_states = grammar.starts.each_with_index.to_h
        end

        # @rbs (String entry, Array[Integer]) -> witness_status
        def simulate(entry, tokens)
          state = @entry_states.fetch(entry)
          Machine.new(@states, @grammar).simulate(state, tokens)
        end

        private

        # @rbs (ReferenceCollection::Collection) -> Array[IR::AutomatonState]
        def build_states(collection)
          states = collection.states.each_with_index.map do |raw_items, state_id|
            build_state(collection, raw_items, state_id)
          end
          states = LALR::OnErrorReductions.apply(@grammar, states)
          LALR::DefaultReductions.apply(states, terminal_ids: @grammar.terminals.map(&:id))
        end

        # @rbs (ReferenceCollection::Collection, Set[Array[Integer]], Integer) -> IR::AutomatonState
        def build_state(collection, raw_items, state_id)
          item_map = Hash.new { |hash, key| hash[key] = Set.new } #: Hash[[Integer, Integer], Set[Integer]]
          raw_items.each do |raw_item|
            production = raw_item.fetch(0) #: Integer
            dot = raw_item.fetch(1) #: Integer
            lookahead = raw_item.fetch(2) #: Integer
            item_map[[production, dot]] << lookahead
          end
          items = item_map.sort.map do |(production, dot), lookaheads|
            IR::AutomatonItem.new(production: production, dot: dot, lookaheads: lookaheads.to_a)
          end
          transitions = collection.transitions.fetch(state_id)
          actions = resolve_actions(items, transitions)
          gotos = {} #: Hash[Integer, Integer]
          transitions.each do |symbol_id, target|
            gotos[symbol_id] = target if @grammar.symbol_by_id(symbol_id)&.nonterminal?
          end
          IR::AutomatonState.new(
            id: state_id, items: items, transitions: transitions,
            actions: actions, gotos: gotos
          )
        end

        # @rbs (Array[IR::AutomatonItem], Hash[Integer, Integer]) -> Hash[Integer, IR::parser_action]
        def resolve_actions(items, transitions)
          candidates = transition_candidates(transitions)
          completed_candidates(items, candidates)
          resolver = LALR::ConflictResolver.new(@grammar)
          candidates.keys.sort.to_h do |token_id|
            action, = resolver.resolve(token_id, candidates.fetch(token_id))
            [token_id, action || { type: :error }]
          end
        end

        # @rbs (Hash[Integer, Integer]) -> Hash[Integer, Array[IR::parser_action]]
        def transition_candidates(transitions)
          candidates = Hash.new { |hash, key| hash[key] = [] } #: Hash[Integer, Array[IR::parser_action]]
          transitions.each do |symbol_id, target|
            next unless @grammar.symbol_by_id(symbol_id)&.terminal?

            candidates[symbol_id] << { type: :shift, state: target }
          end
          candidates
        end

        # @rbs (Array[IR::AutomatonItem], Hash[Integer, Array[IR::parser_action]]) -> void
        def completed_candidates(items, candidates)
          items.each do |item|
            next unless item.dot == rhs_for(item.production).length

            action = if item.production.negative?
                       { type: :accept } #: IR::accept_action
                     else
                       { type: :reduce, production: item.production } #: IR::reduce_action
                     end
            item.lookaheads.each { |lookahead| candidates[lookahead] << action }
          end
        end

        # @rbs (Integer production_id) -> Array[Integer]
        def rhs_for(production_id)
          return [@grammar.symbol(@grammar.starts.fetch(-production_id - 1)).id] if
            production_id.negative?

          @grammar.productions.fetch(production_id).rhs
        end
      end

      # A stack machine shared by the canonical reference and submitted IR.
      class Machine
        # @rbs (Array[IR::AutomatonState] states, IR::Grammar grammar) -> void
        def initialize(states, grammar)
          @states = states
          @grammar = grammar
          @eof = grammar.symbol("$eof") || raise(Ibex::Error, "missing $eof terminal")
        end

        # @rbs (Integer initial, Array[Integer]) -> witness_status
        def simulate(initial, tokens)
          stack = [initial]
          tokens.each do |token_id|
            status = consume(stack, token_id)
            return status unless status == :shifted
          end
          loop do
            status = consume(stack, @eof.id)
            return :accepted if status == :accepted
            return :error unless status == :shifted
          end
        end

        private

        # @rbs (Array[Integer], Integer) -> witness_status
        def consume(stack, token_id)
          steps = 0
          loop do
            steps += 1
            return :error if steps > 10_000

            state = @states.fetch(stack.last)
            action = state.actions.fetch(token_id, state.default_action || { type: :error })
            case action.fetch(:type)
            when :shift
              stack << action.fetch(:state)
              return :shifted
            when :reduce
              production = @grammar.productions.fetch(action.fetch(:production))
              return :error if production.rhs.length >= stack.length

              production.rhs.length.times { stack.pop }
              goto = @states.fetch(stack.last).gotos[production.lhs]
              return :error unless goto

              stack << goto
            when :accept then return :accepted
            else return :error
            end
          end
        end
      end
    end
  end
end
