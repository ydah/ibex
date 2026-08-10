# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

module Ibex
  module Verify
    # Compares resolved ACTION/GOTO behavior over all paired viable prefixes.
    class ActionCorrespondence
      Difference = Struct.new(:kind, :canonical_state, :target_state, :symbol, :canonical, :target,
                              keyword_init: true) do
        def initialize(**values)
          super
          freeze
        end
      end
      Result = Struct.new(:differences, :explored, :truncated, keyword_init: true) do
        def ok?
          differences.empty? && !truncated
        end
      end

      # @rbs (IR::Automaton canonical, IR::Automaton target, ?max_pairs: Integer) -> void
      def initialize(canonical, target, max_pairs: nil)
        @canonical = canonical
        @target = target
        @max_pairs = max_pairs || [canonical.states.length * 8, 1].max
      end

      # @rbs () -> Result
      def verify
        queue = @canonical.entry_states.map do |name, canonical_state|
          [canonical_state, @target.entry_states[name]]
        end
        seen = {}
        differences = []
        truncated = false
        until queue.empty?
          canonical_id, target_id = queue.shift
          key = [canonical_id, target_id]
          next if seen[key]

          if seen.length >= @max_pairs
            truncated = true
            break
          end
          seen[key] = true
          canonical_state = @canonical.states[canonical_id]
          target_state = @target.states[target_id]
          unless canonical_state && target_state
            differences << Difference.new(
              kind: :state, canonical_state: canonical_id, target_state: target_id,
              symbol: nil, canonical: canonical_state, target: target_state
            )
            next
          end
          compare_terminals(canonical_id, target_id, canonical_state, target_state, differences, queue)
          compare_gotos(canonical_id, target_id, canonical_state, target_state, differences, queue)
        end
        Result.new(differences: differences.freeze, explored: seen.length, truncated: truncated)
      end

      private

      # @rbs (Integer, Integer, IR::AutomatonState, IR::AutomatonState,
      #   Array[Difference], Array[Array[Integer]]) -> void
      def compare_terminals(canonical_id, target_id, canonical_state, target_state, differences, queue)
        @canonical.grammar.terminals.each do |terminal|
          left = effective_action(canonical_state, terminal.id)
          right = effective_action(target_state, terminal.id)
          if action_signature(left) != action_signature(right)
            differences << Difference.new(
              kind: :action, canonical_state: canonical_id, target_state: target_id,
              symbol: terminal.id, canonical: left, target: right
            )
          end
          queue << [left[:state], right[:state]] if left[:type] == :shift && right[:type] == :shift
        end
      end

      # @rbs (Integer, Integer, IR::AutomatonState, IR::AutomatonState,
      #   Array[Difference], Array[Array[Integer]]) -> void
      def compare_gotos(canonical_id, target_id, canonical_state, target_state, differences, queue)
        @canonical.grammar.nonterminals.each do |nonterminal|
          left = canonical_state.gotos[nonterminal.id]
          right = target_state.gotos[nonterminal.id]
          if left.nil? != right.nil?
            differences << Difference.new(
              kind: :goto, canonical_state: canonical_id, target_state: target_id,
              symbol: nonterminal.id, canonical: left, target: right
            )
          elsif left && right
            queue << [left, right]
          end
        end
      end

      # @rbs (IR::AutomatonState, Integer) -> IR::parser_action
      def effective_action(state, token_id)
        state.actions.fetch(token_id, state.default_action || { type: :error })
      end

      # @rbs (IR::parser_action) -> Array[Object]
      def action_signature(action)
        case action[:type]
        when :shift then [:shift]
        when :reduce then [:reduce, action[:production]]
        when :accept then [:accept]
        else [:error]
        end
      end
    end
  end
end
# steep:ignore:end
