# frozen_string_literal: true

module Ibex
  module LALR
    # Selects size-reducing default actions without changing any terminal cell.
    module DefaultReductions
      # @rbs!
      #   private def select_default: (Hash[Integer, IR::parser_action] actions, Array[Integer] terminal_ids) -> IR::parser_action?
      #   private def self.select_default: (Hash[Integer, IR::parser_action] actions, Array[Integer] terminal_ids) -> IR::parser_action?

      ERROR_ACTION = { type: :error }.freeze #: IR::error_action

      # @rbs (Array[IR::AutomatonState] states, terminal_ids: Array[Integer]) -> Array[IR::AutomatonState]
      def apply(states, terminal_ids:)
        states.map { |state| optimize(state, terminal_ids: terminal_ids) }
      end
      module_function :apply

      # @rbs (IR::AutomatonState state, terminal_ids: Array[Integer]) -> IR::AutomatonState
      def optimize(state, terminal_ids:)
        return state if state.default_action

        default_action = select_default(state.actions, terminal_ids)
        return state unless default_action

        actions = {} #: Hash[Integer, IR::parser_action]
        terminal_ids.each_with_object(actions) do |token_id, result|
          action = state.actions[token_id]
          result[token_id] = action || ERROR_ACTION unless action == default_action
        end
        IR::AutomatonState.new(id: state.id, items: state.items, transitions: state.transitions,
                               actions: actions, gotos: state.gotos, default_action: default_action,
                               conflicts: state.conflicts)
      end
      module_function :optimize

      # @rbs skip
      private

      # @rbs skip
      def select_default(actions, terminal_ids)
        candidates = [] #: Array[IR::reduce_action]
        actions.each_value do |action|
          next unless action[:type] == :reduce

          reduction = action #: IR::reduce_action
          candidates << reduction
        end
        candidates.uniq!
        candidates.sort_by! { |action| action.fetch(:production) }
        candidate = candidates.max_by do |action|
          saved_entries = actions.count { |_token_id, candidate| candidate == action }
          [saved_entries, -action.fetch(:production)]
        end
        return unless candidate

        optimized_size = terminal_ids.count { |token_id| actions[token_id] != candidate } + 1
        candidate if optimized_size < actions.length
      end
      module_function :select_default

      class << self
        private :select_default
      end
    end
  end
end
