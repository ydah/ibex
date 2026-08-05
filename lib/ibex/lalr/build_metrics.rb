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
      attr_reader :lr0_states #: Integer?
      attr_reader :lr0_items #: Integer?
      attr_reader :canonical_items #: Integer?
      attr_reader :final_items #: Integer?
      attr_reader :final_lookahead_items #: Integer?
      attr_reader :propagation_edges #: Integer?
      attr_reader :ielr_initial_partitions #: Integer?
      attr_reader :ielr_final_partitions #: Integer?

      # @rbs (construction_states: Integer, canonical_states: Integer?, final_states: Integer, strategy: Symbol,
      #   ?lr0_states: Integer?, ?lr0_items: Integer?, ?canonical_items: Integer?, ?final_items: Integer?,
      #   ?final_lookahead_items: Integer?, ?propagation_edges: Integer?, ?ielr_initial_partitions: Integer?,
      #   ?ielr_final_partitions: Integer?) -> void
      def initialize(construction_states:, canonical_states:, final_states:, strategy:, lr0_states: nil, lr0_items: nil,
                     canonical_items: nil, final_items: nil, final_lookahead_items: nil, propagation_edges: nil,
                     ielr_initial_partitions: nil, ielr_final_partitions: nil)
        @construction_states = construction_states
        @canonical_states = canonical_states
        @final_states = final_states
        @strategy = strategy
        @lr0_states = lr0_states
        @lr0_items = lr0_items
        @canonical_items = canonical_items
        @final_items = final_items
        @final_lookahead_items = final_lookahead_items
        @propagation_edges = propagation_edges
        @ielr_initial_partitions = ielr_initial_partitions
        @ielr_final_partitions = ielr_final_partitions
        freeze
      end
    end
  end
end
