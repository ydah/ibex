# frozen_string_literal: true

require_relative "lalr/conflict"
require_relative "lalr/on_error_reductions"
require_relative "lalr/default_reductions"
require_relative "lalr/build_metrics"
require_relative "lalr/lr0_collection"
require_relative "lalr/goto_follows"
require_relative "lalr/lookahead_propagation"
require_relative "lalr/unreachable_states"
require_relative "lalr/ielr/bits"
require_relative "lalr/ielr/inadequacy"
require_relative "lalr/ielr/item_lookaheads"
require_relative "lalr/ielr/split_stability"
require_relative "lalr/ielr/annotator"
require_relative "lalr/ielr/split_state"
require_relative "lalr/ielr/state_splitter"
require_relative "lalr/ielr/pipeline"
require_relative "lalr/direct_lookaheads"
require_relative "lalr/ielr_partition"
require_relative "lalr/builder"
require_relative "lalr/conflict_search_limits"
require_relative "lalr/conflict_search"
require_relative "lalr/counterexample"

module Ibex
  module LALR
    # @rbs!
    #   type lr_item = [Integer, Integer, Integer]
    #   type item_core = [Integer, Integer]
    #   type core_set = Set[item_core]
    #   type item_set = Set[lr_item]
    #   type packed_items = Hash[item_core, Set[Integer]]
    #   type transitions = Array[Hash[Integer, Integer]]
    #   type build_collection = {
    #     construction_states: Integer,
    #     canonical_states: Integer?,
    #     strategy: Symbol,
    #     lr0_states: Integer?,
    #     lr0_items: Integer?,
    #     canonical_items: Integer?,
    #     propagation_edges: Integer?,
    #     ielr_initial_partitions: Integer?,
    #     ielr_final_partitions: Integer?
    #   }
    #   type conflict_fingerprint = [Symbol, String, Array[Integer]]
    #   type lookahead_node = [Integer, Integer, Integer]
    #   type state_partition = Array[Integer]
    #   type derivation_node = Hash[Symbol, Object?]
    #   type search_status = :conflict | :shifted | :accepted
    #   type search_entry = [search_status, ConflictSearch::Configuration]
    #   type search_result = {
    #     sentence_ids: Array[Integer],
    #     lookahead_index: Integer,
    #     interpretations: Array[IR::interpretation]
    #   }
    #   type search_bounds = { max_tokens: Integer, max_configurations: Integer }
    #   type search_outcome = {
    #     status: :found | :not_found | :exhausted,
    #     result: search_result?,
    #     explored: Integer,
    #     exhausted: bool,
    #     bounds: search_bounds
    #   }
    #   type search_counterexample = {
    #     state: Integer,
    #     type: Symbol,
    #     symbol_path: Array[String],
    #     sentence: Array[String],
    #     lookahead_index: Integer,
    #     unifying: bool,
    #     inconclusive: bool,
    #     search: search_outcome,
    #     interpretations: Array[IR::interpretation]
    #   }
  end
end
