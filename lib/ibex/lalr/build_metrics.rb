# frozen_string_literal: true

module Ibex
  module LALR
    # Immutable structural measurements from one automaton build. These counts
    # are intended for diagnostics and benchmarks, not parser behavior.
    class BuildMetrics
      attr_reader :construction_states #: Integer
      attr_reader :canonical_states #: Integer?
      attr_reader :final_states #: Integer
      attr_reader :strategy #: Symbol

      # @rbs (construction_states: Integer, canonical_states: Integer?, final_states: Integer, strategy: Symbol) -> void
      def initialize(construction_states:, canonical_states:, final_states:, strategy:)
        @construction_states = construction_states
        @canonical_states = canonical_states
        @final_states = final_states
        @strategy = strategy
        freeze
      end
    end
  end
end
