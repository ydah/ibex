# frozen_string_literal: true

module Ibex
  module LALR
    # Delays syntax-error detection by filling only otherwise erroneous table
    # cells with one uniquely highest-priority declared reduction.
    module OnErrorReductions
      # @rbs (IR::Grammar grammar, Array[IR::AutomatonState] states) -> Array[IR::AutomatonState]
      def apply(grammar, states)
        priorities = reduction_priorities(grammar)
        return states if priorities.empty?

        terminal_ids = grammar.terminals.reject { |terminal| terminal.name == "error" }.map(&:id)
        states.map { |state| apply_state(grammar, state, priorities, terminal_ids) }
      end
      module_function :apply

      # @rbs (IR::Grammar grammar) -> Hash[Integer, Integer]
      def reduction_priorities(grammar)
        priorities = {} #: Hash[Integer, Integer]
        grammar.recovery[:on_error_reduce].each_with_index do |names, priority|
          names.each do |name|
            symbol = grammar.symbol(name) || raise(Ibex::Error, "missing on-error reduction symbol #{name}")
            priorities[symbol.id] = priority
          end
        end
        priorities
      end

      # @rbs (IR::Grammar grammar, IR::AutomatonState state, Hash[Integer, Integer] priorities,
      #   Array[Integer] terminal_ids) -> IR::AutomatonState
      def apply_state(grammar, state, priorities, terminal_ids)
        production_id = selected_production(grammar, state, priorities)
        return state unless production_id

        reduction = { type: :reduce, production: production_id } #: IR::reduce_action
        actions = state.actions.dup
        terminal_ids.each do |token_id|
          action = actions[token_id]
          actions[token_id] = reduction if action.nil? || action[:type] == :error
        end
        IR::AutomatonState.new(
          id: state.id, items: state.items, transitions: state.transitions,
          actions: actions, gotos: state.gotos, default_action: state.default_action,
          conflicts: state.conflicts
        )
      end

      # @rbs (IR::Grammar grammar, IR::AutomatonState state, Hash[Integer, Integer] priorities) -> Integer?
      def selected_production(grammar, state, priorities)
        candidates = state.items.filter_map do |item|
          next if item.production.negative?

          production = grammar.productions.fetch(item.production)
          next unless item.dot == production.rhs.length

          priority = priorities[production.lhs]
          [priority, production.id] if priority
        end.uniq
        highest = candidates.filter_map(&:first).max
        return unless highest

        productions = candidates.filter_map { |priority, production| production if priority == highest }.uniq
        productions.one? ? productions.fetch(0) : nil
      end

      module_function :reduction_priorities, :apply_state, :selected_production

      class << self
        private :reduction_priorities, :apply_state, :selected_production
      end
    end
  end
end
