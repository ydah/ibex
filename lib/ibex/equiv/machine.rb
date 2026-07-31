# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  class Equiv
    # Immutable, semantic-action-free LR state-stack machine.
    class Machine
      class BudgetExceeded < Ibex::Error; end

      # One product-search component.
      class Configuration
        attr_reader :stack #: Array[Integer]
        attr_reader :status #: Symbol?
        attr_reader :actions #: Integer
        attr_reader :reductions #: Array[Integer]

        # @rbs (stack: Array[Integer], status: Symbol?, actions: Integer, ?reductions: Array[Integer]) -> void
        def initialize(stack:, status:, actions:, reductions: [])
          @stack = stack.freeze
          @status = status
          @actions = actions
          @reductions = reductions.freeze
          freeze
        end
      end

      # @rbs (IR::Automaton automaton, max_actions: Integer, max_stack: Integer) -> void
      def initialize(automaton, max_actions:, max_stack:)
        @automaton = automaton
        @max_actions = max_actions
        @max_stack = max_stack
        @terminals = automaton.grammar.terminals.to_h { |symbol| [symbol.name, symbol.id] }
        @eof_id = @terminals.fetch("$eof")
      end

      # @rbs () -> Configuration
      def start
        entry = @automaton.entry_states.fetch(@automaton.grammar.start)
        Configuration.new(stack: [entry], status: nil, actions: 0, reductions: [])
      end

      # @rbs (Array[String] tokens) -> Configuration
      def run(tokens)
        tokens.reduce(start) { |configuration, token| push(configuration, token) }
      end

      # @rbs (Configuration configuration, String token) -> Configuration
      def push(configuration, token)
        return configuration if configuration.status

        token_id = @terminals[token]
        unless token_id
          return Configuration.new(
            stack: configuration.stack, status: :error, actions: configuration.actions,
            reductions: configuration.reductions
          )
        end

        consume(configuration, token_id, eof: false)
      end

      # @rbs (Configuration configuration) -> Configuration
      def finish(configuration)
        return configuration if configuration.status

        consume(configuration, @eof_id, eof: true)
      end

      private

      # @rbs (Configuration configuration, Integer token_id, eof: bool) -> Configuration
      def consume(configuration, token_id, eof:)
        stack = configuration.stack.dup
        actions = configuration.actions
        reductions = configuration.reductions.dup
        loop do
          actions += 1
          enforce_action_budget!(actions)
          state = @automaton.states.fetch(stack.fetch(-1))
          action = state.actions.fetch(token_id, state.default_action || { type: :error })
          case action.fetch(:type)
          when :shift
            shift = action #: IR::shift_action
            stack << shift.fetch(:state)
            enforce_stack_budget!(stack)
            return Configuration.new(stack: stack, status: nil, actions: actions, reductions: reductions) unless eof
          when :reduce
            reduce = action #: IR::reduce_action
            production_id = reduce.fetch(:production)
            apply_reduction!(stack, production_id)
            reductions << production_id
            enforce_stack_budget!(stack)
          when :accept
            return Configuration.new(
              stack: stack, status: :accepted, actions: actions, reductions: reductions
            )
          when :error
            return Configuration.new(stack: stack, status: :error, actions: actions, reductions: reductions)
          else
            raise Ibex::Error, "(equiv):1:1: unknown parser action #{action.inspect}"
          end
        end
      end

      # @rbs (Array[Integer] stack, Integer production_id) -> void
      def apply_reduction!(stack, production_id)
        production = @automaton.grammar.productions.fetch(production_id)
        if production.rhs.length >= stack.length
          raise Ibex::Error, "(equiv):1:1: production #{production_id} underflows the state stack"
        end

        stack.pop(production.rhs.length)
        state = @automaton.states.fetch(stack.fetch(-1))
        target = state.gotos[production.lhs]
        raise Ibex::Error, "(equiv):1:1: missing goto after production #{production_id}" unless target

        stack << target
      end

      # @rbs (Integer actions) -> void
      def enforce_action_budget!(actions)
        return if actions <= @max_actions

        raise BudgetExceeded, "(equiv):1:1: simulation exceeded #{@max_actions} actions"
      end

      # @rbs (Array[Integer] stack) -> void
      def enforce_stack_budget!(stack)
        return if stack.length <= @max_stack

        raise BudgetExceeded, "(equiv):1:1: simulation exceeded stack depth #{@max_stack}"
      end
    end
  end
end
