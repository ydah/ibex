# frozen_string_literal: true

module Ibex
  module LALR
    # Immutable structural measurements from one automaton build. These counts
    # are intended for diagnostics and benchmarks, not parser behavior.
    class BuildMetrics
      attr_reader :canonical_states #: Integer
      attr_reader :final_states #: Integer

      # @rbs (canonical_states: Integer, final_states: Integer) -> void
      def initialize(canonical_states:, final_states:)
        @canonical_states = canonical_states
        @final_states = final_states
        freeze
      end
    end
  end
end
