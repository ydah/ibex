# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require_relative "../lr0_collection"
require_relative "../goto_follows"
require_relative "../lookahead_propagation"
require_relative "state_splitter"

# The method follows the fixed six-phase pipeline as one transaction.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength

module Ibex
  module LALR
    module IELR
      # Coordinates the canonical-free direct IELR phases.  The returned
      # profile deliberately reports canonical metrics as unavailable.
      class Pipeline
        # @rbs (IR::Grammar grammar, Analysis::Sets sets, ?starts: Array[String]?, ?profile: bool) -> void
        def initialize(grammar, sets, starts: nil, profile: false)
          @grammar = grammar
          @sets = sets
          @starts = starts || grammar.starts
          @profile = profile
        end

        # @rbs () -> [Array[packed_items], transitions, LALR::build_collection]
        def build
          states, transitions = LR0Collection.new(@grammar, starts: @starts).build
          seeds = @starts.each_with_index.map do |name, index|
            augmented = -1 - @grammar.starts.index(name)
            [index, [augmented, 0], 0]
          end
          initial_propagation = LookaheadPropagation.new(
            @grammar, @sets, states, transitions, seeds: seeds
          )
          items = initial_propagation.build
          goto_follows = GotoFollows.new(
            @grammar, @sets, states, transitions, @starts.each_index.to_a, start_names: @starts
          )
          splitter = StateSplitter.new(@grammar, states, transitions, items, goto_follows)
          _split_items, split_transitions = splitter.build
          split_states = splitter.states.map { |state| states.fetch(state.lalr_isocore) }
          phase4_items = LookaheadPropagation.new(
            @grammar, @sets, split_states, split_transitions, seeds: seeds
          ).build
          profile = {
            construction_states: phase4_items.length,
            canonical_states: nil,
            strategy: :ielr_direct,
            lr0_states: @profile ? states.length : nil,
            lr0_items: @profile ? states.sum(&:length) : nil,
            canonical_items: nil,
            propagation_edges: @profile ? initial_propagation.propagation_edge_count : nil,
            ielr_initial_partitions: nil,
            ielr_final_partitions: nil,
            ielr_annotations: splitter.annotations.sum(&:length),
            ielr_annotated_states: splitter.annotations.count { |entries| !entries.empty? },
            ielr_inadequacies: splitter.inadequacies.sum(&:length),
            ielr_split_stable_discarded: splitter.split_stable_discarded,
            ielr_lalr_states: states.length,
            ielr_split_states: splitter.split_states,
            ielr_unreachable_removed: 0,
            ielr_remergeable_candidates: nil
          }
          [phase4_items, split_transitions, profile]
        end
      end
    end
  end
end
# steep:ignore:end

# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
