# frozen_string_literal: true

require_relative "../lalr/conflict_search_limits"

module Ibex
  module ErrorMessages
    # Finds deterministic shortest token sentences that reach each syntax
    # error state without running semantic actions.
    class SentenceSearch
      DEFAULT_MAX_TOKENS = LALR::ConflictSearchLimits::DEFAULT_MAX_TOKENS #: Integer
      DEFAULT_MAX_CONFIGURATIONS = LALR::ConflictSearchLimits::DEFAULT_MAX_CONFIGURATIONS #: Integer

      Witness = Struct.new(
        :entry, #: String
        :tokens, #: Array[String]
        :state, #: Integer
        keyword_init: true
      )

      # @rbs @automaton: IR::Automaton
      # @rbs @grammar: IR::Grammar
      # @rbs @max_tokens: Integer
      # @rbs @max_configurations: Integer
      # @rbs @candidates: Array[IR::GrammarSymbol]
      # @rbs @input_candidates: Array[IR::GrammarSymbol]
      # @rbs @explored: Integer

      # @rbs (IR::Automaton automaton, ?max_tokens: Integer, ?max_configurations: Integer) -> void
      def initialize(automaton, max_tokens: DEFAULT_MAX_TOKENS,
                     max_configurations: DEFAULT_MAX_CONFIGURATIONS)
        LALR::ConflictSearchLimits.validate!(
          max_tokens: max_tokens, max_configurations: max_configurations
        )
        @automaton = automaton
        @grammar = automaton.grammar
        @max_tokens = max_tokens
        @max_configurations = max_configurations
        @candidates = grammar_terminals
        @input_candidates = @candidates.reject { |symbol| symbol.id.zero? }
        @explored = 0
      end

      # @rbs () -> Hash[Integer, Witness]
      def all
        targets = ErrorMessages.error_states(@automaton).to_h { |state| [state.id, true] }
        witnesses = {} #: Hash[Integer, Witness]
        @automaton.entry_states.each do |entry, initial_state|
          search_entry(entry, initial_state, targets, witnesses)
          break if witnesses.length == targets.length
        end
        witnesses.sort.to_h.freeze
      end

      # @rbs (Array[String] tokens, ?entry: String?) -> Integer?
      def state_for(tokens, entry: nil)
        return nil if tokens.empty?

        start = entry || @grammar.start
        initial = @automaton.entry_states[start]
        return nil unless initial

        states = [initial]
        tokens.each_with_index do |name, index|
          status, value = consume_sentence_token(states, name, index == tokens.length - 1)
          return value if status == :error && value.is_a?(Integer)
          return nil unless status == :continue && value.is_a?(Array)

          states = value
        end
        nil
      end

      private

      # @rbs (Array[Integer] states, String name, bool final) ->
      #   [Symbol, Array[Integer] | Integer | nil]
      def consume_sentence_token(states, name, final)
        symbol = sentence_symbol(name, final)
        return [:invalid, nil] unless symbol

        status, value = advance(states, symbol.id)
        return [:error, value] if status == :error && final && value.is_a?(Integer)
        return [:continue, value] if status == :shift && value.is_a?(Array)

        [:invalid, nil]
      end

      # @rbs (String name, bool final) -> IR::GrammarSymbol?
      def sentence_symbol(name, final)
        symbol = @grammar.symbol(name)
        return nil unless symbol&.terminal?
        return nil if symbol.name == "error" || (symbol.id.zero? && !final)

        symbol
      end

      # @rbs () -> Array[IR::GrammarSymbol]
      def grammar_terminals
        @grammar.terminals
                .reject { |symbol| symbol.name == "error" }
                .sort_by { |symbol| [symbol.id.zero? ? 1 : 0, symbol.name] }
      end

      # @rbs (String entry, Integer initial_state, Hash[Integer, bool] targets,
      #   Hash[Integer, Witness] witnesses) -> void
      def search_entry(entry, initial_state, targets, witnesses)
        queue = [[[initial_state], Array.new(0)]] #: Array[[Array[Integer], Array[String]]]
        visited = { [initial_state] => true }
        until queue.empty? || witnesses.length == targets.length
          states, prefix = queue.shift
          count_configuration!
          collect_errors(entry, states, prefix, targets, witnesses)
          enqueue_shifts(queue, visited, states, prefix) if prefix.length < @max_tokens - 1
        end
      end

      # @rbs (String entry, Array[Integer] states, Array[String] prefix, Hash[Integer, bool] targets,
      #   Hash[Integer, Witness] witnesses) -> void
      def collect_errors(entry, states, prefix, targets, witnesses)
        @candidates.each do |symbol|
          status, state = advance(states, symbol.id)
          next unless status == :error && state.is_a?(Integer)

          error_state = state #: Integer
          next unless targets[error_state] && !witnesses[error_state]

          witnesses[error_state] = Witness.new(
            entry: entry, tokens: (prefix + [symbol.name]).freeze, state: error_state
          ).freeze
        end
      end

      # @rbs (Array[[Array[Integer], Array[String]]] queue, Hash[Array[Integer], bool] visited,
      #   Array[Integer] states, Array[String] prefix) -> void
      def enqueue_shifts(queue, visited, states, prefix)
        @input_candidates.each do |symbol|
          status, shifted = advance(states, symbol.id)
          next unless status == :shift && shifted.is_a?(Array)

          shifted_states = shifted #: Array[Integer]
          next if visited[shifted_states]

          visited[shifted_states] = true
          queue << [shifted_states, prefix + [symbol.name]]
        end
      end

      # @rbs (Array[Integer] initial, Integer token_id) -> [Symbol, Array[Integer] | Integer | nil]
      def advance(initial, token_id)
        states = initial
        visited = {} #: Hash[Array[Integer], bool]
        loop do
          return [:invalid, nil] if visited[states]

          visited[states] = true
          state = @automaton.states.fetch(states.last)
          action = state.actions[token_id] || state.default_action
          return [:error, state.id] if action.nil? || action[:type] == :error

          case action[:type]
          when :shift
            shift = action #: IR::shift_action
            return [:shift, (states + [shift[:state]]).freeze]
          when :reduce
            reduce = action #: IR::reduce_action
            states = reduce_stack(states, reduce[:production])
            return [:invalid, nil] unless states
          when :accept
            return [:accept, nil]
          else
            return [:invalid, nil]
          end
        end
      end

      # @rbs (Array[Integer] states, Integer production_id) -> Array[Integer]?
      def reduce_stack(states, production_id)
        production = @grammar.productions.fetch(production_id)
        return nil if production.rhs.length >= states.length

        remaining = states.take(states.length - production.rhs.length)
        target = @automaton.states.fetch(remaining.last).gotos[production.lhs]
        target && (remaining + [target]).freeze
      end

      # @rbs () -> void
      def count_configuration!
        @explored += 1
        return if @explored <= @max_configurations

        raise Ibex::Error,
              "(messages):1:1: error-sentence search exceeded #{@max_configurations} configurations"
      end
    end
  end
end
