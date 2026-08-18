# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module LALR
    # Immutable structural measurements from one automaton build.
    BuildMetrics = Struct.new(
      :construction_states,
      :canonical_states,
      :final_states,
      :strategy,
      :lr0_states,
      :lr0_items,
      :canonical_items,
      :final_items,
      :final_lookahead_items,
      :propagation_edges,
      :ielr_initial_partitions,
      :ielr_final_partitions,
      :ielr_annotations,
      :ielr_annotated_states,
      :ielr_inadequacies,
      :ielr_split_stable_discarded,
      :ielr_lalr_states,
      :ielr_split_states,
      :ielr_unreachable_removed,
      :ielr_remergeable_candidates,
      keyword_init: true
    ) do
      # @rbs (construction_states: Integer, canonical_states: Integer?, final_states: Integer, strategy: Symbol,
      #   ?lr0_states: Integer?, ?lr0_items: Integer?, ?canonical_items: Integer?, ?final_items: Integer?,
      #   ?final_lookahead_items: Integer?, ?propagation_edges: Integer?, ?ielr_initial_partitions: Integer?,
      #   ?ielr_final_partitions: Integer?, ?ielr_annotations: Integer?, ?ielr_annotated_states: Integer?,
      #   ?ielr_inadequacies: Integer?, ?ielr_split_stable_discarded: Integer?, ?ielr_lalr_states: Integer?,
      #   ?ielr_split_states: Integer?, ?ielr_unreachable_removed: Integer?,
      #   ?ielr_remergeable_candidates: Integer?) -> void
      def initialize(construction_states:, canonical_states:, final_states:, strategy:, **optional)
        super
        freeze
      end
    end
  end
end
