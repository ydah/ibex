# frozen_string_literal: true

require_relative "lalr/conflict"
require_relative "lalr/default_reductions"
require_relative "lalr/builder"
require_relative "lalr/conflict_search_limits"
require_relative "lalr/conflict_search"
require_relative "lalr/counterexample"

module Ibex
  module LALR
    # @rbs!
    #   type lr_item = [Integer, Integer, Integer]
    #   type item_core = [Integer, Integer]
    #   type item_set = Set[lr_item]
    #   type packed_items = Hash[item_core, Set[Integer]]
    #   type transitions = Array[Hash[Integer, Integer]]
    #   type derivation_node = Hash[Symbol, untyped]
    #   type search_status = :conflict | :shifted | :accepted
    #   type search_entry = [search_status, ConflictSearch::Configuration]
    #   type search_result = {
    #     sentence_ids: Array[Integer],
    #     lookahead_index: Integer,
    #     interpretations: Array[IR::interpretation]
    #   }
  end
end
