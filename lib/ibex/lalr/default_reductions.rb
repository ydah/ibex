# frozen_string_literal: true

module Ibex
  module LALR
    # Selects size-reducing default actions without changing any terminal cell.
    module DefaultReductions
      ERROR_ACTION = { type: :error }.freeze

      module_function

      def apply(states, terminal_ids:)
        states.map { |state| optimize(state, terminal_ids: terminal_ids) }
      end

      def optimize(state, terminal_ids:)
        return state if state.default_action

        default_action = select_default(state.actions, terminal_ids)
        return state unless default_action

        actions = {} #: Hash[untyped, untyped]
        terminal_ids.each_with_object(actions) do |token_id, result|
          action = state.actions[token_id]
          result[token_id] = action || ERROR_ACTION unless action == default_action
        end
        IR::AutomatonState.new(id: state.id, items: state.items, transitions: state.transitions,
                               actions: actions, gotos: state.gotos, default_action: default_action,
                               conflicts: state.conflicts)
      end

      def select_default(actions, terminal_ids)
        candidates = actions.values.select { |action| action[:type] == :reduce }.uniq
        candidates.sort_by! { |action| action.fetch(:production) }
        candidate = candidates.max_by do |action|
          saved_entries = actions.count { |_token_id, candidate| candidate == action }
          [saved_entries, -action.fetch(:production)]
        end
        return unless candidate

        optimized_size = terminal_ids.count { |token_id| actions[token_id] != candidate } + 1
        candidate if optimized_size < actions.length
      end
      private_class_method :select_default
    end
  end
end
