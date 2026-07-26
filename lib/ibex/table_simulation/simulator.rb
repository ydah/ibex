# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../error"

module Ibex
  module TableSimulation
    # Deterministic, semantic-action-free table interpreter.
    class Simulator
      DEFAULT_MAX_STEPS = 100_000 #: Integer
      DEFAULT_MAX_STACK = 10_000 #: Integer
      EOF_NAME = "$eof" #: String
      ERROR_NAME = "error" #: String
      IMPLICIT_ERROR = { type: :error }.freeze #: IR::error_action

      attr_reader :automaton #: IR::Automaton
      attr_reader :max_steps #: Integer
      attr_reader :max_stack #: Integer
      attr_reader :eof #: IR::GrammarSymbol

      # @rbs (IR::Automaton automaton, ?max_steps: Integer, ?max_stack: Integer) -> void
      def initialize(automaton, max_steps: DEFAULT_MAX_STEPS, max_stack: DEFAULT_MAX_STACK)
        raise ArgumentError, "max_steps must be positive" unless max_steps.positive?
        raise ArgumentError, "max_stack must be positive" unless max_stack.positive?

        @automaton = automaton
        @max_steps = max_steps
        @max_stack = max_stack
        @terminals = automaton.grammar.terminals.to_h { |symbol| [symbol.name, symbol] }.freeze
        @terminal_aliases = terminal_aliases(automaton.grammar.terminals).freeze
        @eof = @terminals[EOF_NAME] || raise(Ibex::Error, "(debug):1:1: automaton has no $eof terminal")
      end

      # @rbs () -> Session
      def start
        Session.new(self)
      end

      # @rbs (Array[String] tokens) -> Result
      def simulate(tokens)
        session = start
        tokens.each do |token|
          session.push(token)
          break if session.status
        end
        session.finish
      end

      # @rbs (String spelling) -> IR::GrammarSymbol
      def terminal(spelling)
        if [EOF_NAME, ERROR_NAME].include?(spelling)
          raise Ibex::Error, "(debug):1:1: reserved terminal #{spelling.inspect} cannot be supplied"
        end

        terminal = @terminals[spelling]
        return terminal if terminal

        empty = [] #: Array[IR::GrammarSymbol]
        aliases = @terminal_aliases.fetch(spelling, empty)
        return aliases.first if aliases.length == 1

        if aliases.length > 1
          names = aliases.map(&:name).sort.join(", ")
          raise Ibex::Error, "(debug):1:1: terminal display name #{spelling.inspect} is ambiguous: #{names}"
        end

        raise Ibex::Error, "(debug):1:1: unknown terminal #{spelling.inspect}"
      end

      private

      # @rbs (Array[IR::GrammarSymbol] terminals) -> Hash[String, Array[IR::GrammarSymbol]]
      def terminal_aliases(terminals)
        aliases = Hash.new { |hash, key| hash[key] = [] } #: Hash[String, Array[IR::GrammarSymbol]]
        terminals.each do |terminal|
          aliases[terminal.display_name] << terminal if terminal.display_name
        end
        aliases.each_value(&:freeze)
        aliases
      end
    end

    # Stateful token-at-a-time table simulation session.
    class Session
      # @rbs @steps: Array[Step]
      # @rbs @tokens: Array[String]

      attr_reader :status #: Symbol?

      # @rbs (Simulator simulator) -> void
      def initialize(simulator)
        @simulator = simulator
        @state_stack = [0] #: Array[Integer]
        @status = nil
        @steps = []
        @tokens = []
        @finished = false
      end

      # @rbs (String spelling) -> Array[Step]
      def push(spelling)
        ensure_active!
        terminal = @simulator.terminal(spelling)
        @tokens << terminal.name
        process(terminal, eof: false)
      end

      # @rbs () -> Array[Step]
      def steps = @steps.dup.freeze

      # @rbs () -> Array[String]
      def tokens = @tokens.dup.freeze

      # @rbs () -> Result
      def finish
        raise Ibex::Error, "(debug):1:1: simulation session is already finished" if @finished

        @finished = true
        process(@simulator.eof, eof: true) until @status
        Result.new(
          grammar_digest: @simulator.automaton.grammar_digest,
          algorithm: @simulator.automaton.algorithm,
          tokens: @tokens,
          status: @status || raise(Ibex::Error, "(debug):1:1: simulation did not terminate"),
          steps: @steps
        )
      end

      private

      # @rbs (IR::GrammarSymbol terminal, eof: bool) -> Array[Step]
      def process(terminal, eof:)
        first = @steps.length
        loop do
          state = current_state
          action, source = action_for(state, terminal.id)
          case action.fetch(:type)
          when :shift
            record_shift(state, terminal, action, source)
            next if eof

            break
          when :reduce then record_reduce(state, terminal, action, source)
          when :accept
            record_terminal(state, terminal, "accept", source)
            @status = :accepted
            break
          when :error
            record_terminal(state, terminal, "error", source)
            @status = :error
            break
          else raise Ibex::Error, "(debug):1:1: unknown table action #{action.inspect}"
          end
        end
        @steps.drop(first).freeze
      end

      # @rbs (IR::AutomatonState state, Integer token_id) -> [IR::parser_action, String]
      def action_for(state, token_id)
        return [state.actions.fetch(token_id), "explicit"] if state.actions.key?(token_id)
        return [state.default_action, "default"] if state.default_action

        [Simulator::IMPLICIT_ERROR, "implicit"]
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, IR::parser_action action, String source) -> void
      def record_shift(state, terminal, action, source)
        shift = action #: IR::shift_action
        before = @state_stack.length
        target = shift.fetch(:state)
        @state_stack << target
        enforce_stack_budget!
        append_step(state, terminal, "shift", source, target_state: target, before: before)
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, IR::parser_action action, String source) -> void
      def record_reduce(state, terminal, action, source)
        reduction = action #: IR::reduce_action
        production_id = reduction.fetch(:production)
        production = @simulator.automaton.grammar.productions.fetch(production_id)
        length = production.rhs.length
        before = @state_stack.length
        if length >= before
          raise Ibex::Error, "(debug):1:1: production #{production_id} underflows the simulated state stack"
        end

        @state_stack.pop(length)
        goto = current_state.gotos[production.lhs]
        unless goto
          raise Ibex::Error, "(debug):1:1: missing goto for production #{production_id} from state #{current_state.id}"
        end

        @state_stack << goto
        enforce_stack_budget!
        lhs = @simulator.automaton.grammar.symbol_by_id(production.lhs)
        raise Ibex::Error, "(debug):1:1: missing lhs symbol #{production.lhs}" unless lhs

        append_step(
          state, terminal, "reduce", source,
          production_id: production_id, lhs: lhs.name, rhs_length: length,
          target_state: goto, before: before
        )
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, String action, String source) -> void
      def record_terminal(state, terminal, action, source)
        append_step(state, terminal, action, source, before: @state_stack.length)
      end

      # @rbs (IR::AutomatonState state, IR::GrammarSymbol terminal, String action, String source,
      #   before: Integer, ?production_id: Integer?, ?lhs: String?, ?rhs_length: Integer?,
      #   ?target_state: Integer?) -> void
      def append_step(state, terminal, action, source, before:, production_id: nil, lhs: nil, rhs_length: nil,
                      target_state: nil)
        raise Ibex::Error, "(debug):1:1: simulation exceeded #{@simulator.max_steps} actions" \
          if @steps.length >= @simulator.max_steps

        @steps << Step.new(
          sequence: @steps.length + 1,
          state: state.id,
          token_id: terminal.id,
          token: terminal.display_name || terminal.name,
          action: action,
          action_source: source,
          production_id: production_id,
          lhs: lhs,
          rhs_length: rhs_length,
          target_state: target_state,
          stack_depth_before: before,
          stack_depth_after: @state_stack.length
        )
      end

      # @rbs () -> IR::AutomatonState
      def current_state
        id = @state_stack.last || raise(Ibex::Error, "(debug):1:1: simulated state stack is empty")
        @simulator.automaton.states.fetch(id)
      end

      # @rbs () -> void
      def enforce_stack_budget!
        return if @state_stack.length <= @simulator.max_stack

        raise Ibex::Error, "(debug):1:1: simulation exceeded stack depth #{@simulator.max_stack}"
      end

      # @rbs () -> void
      def ensure_active!
        raise Ibex::Error, "(debug):1:1: simulation session is already finished" if @finished || @status
      end
    end
  end
end
