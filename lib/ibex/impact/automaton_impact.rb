# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Impact
    # Maps propagated grammar symbols to parser states and conflict changes.
    class AutomatonImpact
      # @rbs @automaton: IR::Automaton
      # @rbs @symbol_ids: Array[Integer]
      # @rbs @production_ids: Array[Integer]
      attr_reader :affected_states #: Array[Integer]
      attr_reader :production_ids #: Array[Integer]
      attr_reader :conflict_states #: Array[Integer]

      # @rbs (IR::Automaton automaton, Array[Integer]) -> void
      def initialize(automaton, symbol_ids)
        @automaton = automaton
        @symbol_ids = symbol_ids.uniq.sort #: Array[Integer]
        @production_ids = affected_productions
        @affected_states = affected_state_ids
        @conflict_states = conflict_state_ids
        freeze
      end

      # @rbs (Hash[Symbol, Object?] diff) -> Hash[Symbol, Object?]
      def conflict_changes(diff)
        diff.fetch(:conflicts) #: Hash[Symbol, Object?]
      end

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        { states: @affected_states, productions: @production_ids, conflict_states: @conflict_states }
      end

      private

      # @rbs () -> Array[Integer]
      def affected_productions
        @automaton.grammar.productions.filter_map do |production|
          production.id if @symbol_ids.include?(production.lhs) || production.rhs.any? { |id| @symbol_ids.include?(id) }
        end.sort
      end

      # @rbs () -> Array[Integer]
      def affected_state_ids
        @automaton.states.filter_map do |state|
          state.id if state.items.any? { |item| @production_ids.include?(item.production) }
        end.sort
      end

      # @rbs () -> Array[Integer]
      def conflict_state_ids
        @automaton.states.filter_map { |state| state.id unless state.conflicts.empty? }.sort
      end
    end
  end
end
