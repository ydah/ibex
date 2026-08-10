# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

module Ibex
  module LALR
    # Optional post-resolution compaction.  It is intentionally off by
    # default because state numbers are part of diagnostics and golden output.
    module UnreachableStates
      module_function

      # @rbs (Array[IR::AutomatonState] states, Array[Integer] start_states) ->
      #   [Array[IR::AutomatonState], Hash[Integer, Integer]]
      def remove(states, start_states)
        reachable = reachable_states(states, start_states)
        mapping = reachable.each_with_index.to_h { |old_id, new_id| [old_id, new_id] }
        return [states, mapping] if reachable.length == states.length

        compacted = reachable.map do |old_id|
          state = states.fetch(old_id)
          transitions = remap_edges(state.transitions, mapping)
          gotos = remap_edges(state.gotos, mapping)
          actions = state.actions.transform_values { |action| remap_action(action, mapping) }
          default_action = remap_action(state.default_action, mapping)
          conflicts = state.conflicts.map { |conflict| remap_conflict(conflict, mapping) }
          IR::AutomatonState.new(
            id: mapping.fetch(old_id), items: state.items, transitions: transitions,
            actions: actions, gotos: gotos, default_action: default_action, conflicts: conflicts
          )
        end
        [compacted, mapping]
      end

      # @rbs (Array[IR::AutomatonState], Array[Integer]) -> Array[Integer]
      def reachable_states(states, start_states)
        visited = {}
        queue = start_states.dup
        until queue.empty?
          state_id = queue.shift
          next if visited[state_id]

          visited[state_id] = true
          state = states.fetch(state_id)
          state.gotos.each_value { |target| queue << target }
          state.actions.each_value do |action|
            queue << action[:state] if action[:type] == :shift
          end
        end
        visited.keys.sort
      end

      # @rbs (Hash[Integer, Integer], Hash[Integer, Integer]) -> Hash[Integer, Integer]
      def remap_edges(edges, mapping)
        edges.each_with_object({}) do |(symbol_id, target), result|
          result[symbol_id] = mapping[target] if mapping.key?(target)
        end
      end

      # @rbs (IR::parser_action?, Hash[Integer, Integer]) -> IR::parser_action?
      def remap_action(action, mapping)
        return nil unless action
        return action unless action[:type] == :shift
        return { type: :shift, state: mapping.fetch(action[:state]) } if mapping.key?(action[:state])

        { type: :error }
      end

      # @rbs (IR::conflict, Hash[Integer, Integer]) -> IR::conflict
      def remap_conflict(conflict, mapping)
        result = conflict.dup
        if result[:type] == :shift_reduce && mapping.key?(result[:shift_to])
          result[:shift_to] = mapping.fetch(result[:shift_to])
        end
        result
      end
    end
  end
end
# steep:ignore:end
