# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require "set"
require_relative "bits"
require_relative "inadequacy"
require_relative "item_lookaheads"
require_relative "split_stability"

# The methods follow the paper's matrix definitions directly.
# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

module Ibex
  module LALR
    module IELR
      # Finds grammar-relative inadequacies and traces their possible
      # manifestations through predecessor states.
      class Annotator
        attr_reader :annotation_lists #: Array[Array[Annotation]]
        attr_reader :inadequacies #: Array[Array[Inadequacy]]
        attr_reader :item_lookaheads #: ItemLookaheads
        attr_reader :split_stable_discarded #: Integer

        # @rbs (IR::Grammar grammar, Array[core_set] states, transitions transitions,
        #   Array[packed_items] items, GotoFollows goto_follows, ?resolver: ConflictResolver?) -> void
        def initialize(grammar, states, transitions, items, goto_follows, resolver: nil)
          @grammar = grammar
          @states = states
          @transitions = transitions
          @items = items
          @goto_follows = goto_follows
          @resolver = resolver || ConflictResolver.new(grammar)
          @kernel_cores = states.map { |state| kernel_items(state) }
          @item_lookaheads = ItemLookaheads.new(
            grammar, goto_follows, @kernel_cores, goto_follows.predecessors,
            start_states: (0...grammar.starts.length).to_a
          )
          @annotation_lists = Array.new(states.length) { [] }
          @keys = Array.new(states.length) { Set.new }
          @inadequacies = Array.new(states.length) { [] }
          @next_id = 0
          @split_stable_discarded = 0
        end

        # @rbs () -> Array[Array[Annotation]]
        def build
          @states.each_index do |state_id|
            @inadequacies[state_id] = build_inadequacies(state_id)
            @inadequacies.fetch(state_id).each do |inadequacy|
              register?(state_id, annotate_manifestation(state_id, inadequacy))
            end
          end
          worklist = @annotation_lists.each_with_index.flat_map do |annotations, state_id|
            annotations.map { |annotation| [state_id, annotation] }
          end
          cursor = 0
          while cursor < worklist.length
            state_id, annotation = worklist.fetch(cursor)
            cursor += 1
            @goto_follows.predecessors.fetch(state_id).each do |previous|
              derived = annotate_predecessor(previous, state_id, annotation)
              worklist << [previous, derived] if register?(previous, derived)
            end
          end
          @annotation_lists
        end

        private

        # @rbs (Integer state_id) -> Array[Inadequacy]
        def build_inadequacies(state_id)
          @grammar.terminals.filter_map do |terminal|
            contributions = contributions_for(state_id, terminal.id)
            next if contributions.length < 2

            inadequacy = Inadequacy.new(state: state_id, token: terminal.id, contributions: contributions, id: @next_id)
            @next_id += 1
            inadequacy
          end
        end

        # @rbs (Integer state_id, Integer token_id) -> Array[Array[Symbol, Integer?]]
        def contributions_for(state_id, token_id)
          reductions = @items.fetch(state_id).filter_map do |(production_id, dot), lookaheads|
            next unless dot == rhs_for(production_id).length && lookaheads.include?(token_id)

            production_id
          end.sort
          contributions = reductions.select(&:negative?).map { |production_id| [:accept, production_id] }
          symbol = @grammar.symbol_by_id(token_id)
          contributions << [:shift, nil] if symbol&.terminal? && @transitions.fetch(state_id).key?(token_id)
          contributions.concat(reductions.reject(&:negative?).map { |production_id| [:reduce, production_id] })
          contributions
        end

        # @rbs (Integer state_id, Inadequacy inadequacy) -> Annotation
        def annotate_manifestation(state_id, inadequacy)
          matrix = inadequacy.contributions.map do |kind, production_id|
            next nil if kind == :shift

            rhs = rhs_for(production_id)
            if rhs.empty?
              compute_lhs_contributions(state_id, lhs_for(production_id), inadequacy.token)
            else
              completed_kernel_mask(state_id, production_id, rhs.length)
            end
          end
          Annotation.new(inadequacy: inadequacy, matrix: matrix)
        end

        # @rbs (Integer state_id, Integer successor_id, Annotation annotation) -> Annotation
        def annotate_predecessor(state_id, successor_id, annotation)
          token = annotation.inadequacy.token
          cores = @kernel_cores.fetch(successor_id)
          matrix = annotation.matrix.map do |row|
            next nil if row.nil?
            next nil if always_via_lhs?(state_id, cores, row, token)

            project_row(state_id, cores, row, token)
          end
          Annotation.new(inadequacy: annotation.inadequacy, matrix: matrix)
        end

        # @rbs (Integer state_id, Array[item_core], Integer, Integer) -> bool
        def always_via_lhs?(state_id, cores, row, token)
          Bits.each_set_bit(row).any? do |index|
            production_id, dot = cores.fetch(index)
            next false unless dot == 1

            compute_lhs_contributions(state_id, lhs_for(production_id), token).nil?
          end
        end

        # @rbs (Integer state_id, Array[item_core], Integer, Integer) -> Integer
        def project_row(state_id, cores, row, token)
          Bits.each_set_bit(row).reduce(0) do |mask, index|
            production_id, dot = cores.fetch(index)
            if dot > 1
              previous = kernel_index_of(state_id, production_id, dot - 1)
              next mask unless previous && item_lookaheads.fetch(state_id, previous).anybits?(1 << token)

              mask | (1 << previous)
            else
              lhs_mask = compute_lhs_contributions(state_id, lhs_for(production_id), token)
              mask | lhs_mask.to_i
            end
          end
        end

        # @rbs (Integer state_id, Integer production_id, Integer length) -> Integer
        def completed_kernel_mask(state_id, production_id, length)
          index = kernel_index_of(state_id, production_id, length)
          index ? (1 << index) : 0
        end

        # @rbs (Integer state_id, Integer lhs_id, Integer token_id) -> Integer?
        def compute_lhs_contributions(state_id, lhs_id, token_id)
          goto_id = @goto_follows.goto_for(state_id, lhs_id)
          raise Ibex::Error, "missing goto for #{lhs_id} from #{state_id}" unless goto_id
          return nil if @goto_follows.always_follows.fetch(goto_id).anybits?(1 << token_id)

          mask = 0
          Bits.each_set_bit(@goto_follows.follow_kernel_items.fetch(goto_id)) do |index|
            mask |= 1 << index if @item_lookaheads.fetch(state_id, index).anybits?(1 << token_id)
          end
          mask
        end

        # @rbs (Integer state_id, Annotation annotation) -> bool
        def register?(state_id, annotation)
          if SplitStability.split_stable?(annotation, @resolver)
            @split_stable_discarded += 1
            return false
          end

          key = annotation.key
          return false unless @keys.fetch(state_id).add?(key)

          @annotation_lists.fetch(state_id) << annotation
          true
        end

        # @rbs (Integer state_id, Integer production_id) -> Integer
        def lhs_for(production_id)
          return @grammar.symbol(@grammar.starts.fetch(-production_id - 1)).id if production_id.negative?

          @grammar.productions.fetch(production_id).lhs
        end

        # @rbs (Integer production_id) -> Array[Integer]
        def rhs_for(production_id)
          return [lhs_for(production_id)] if production_id.negative?

          @grammar.productions.fetch(production_id).rhs
        end

        # @rbs (core_set items) -> Array[item_core]
        def kernel_items(items)
          items.select { |production_id, dot| production_id.negative? || dot.positive? }.to_a.sort
        end

        # @rbs (Integer state_id, Integer production_id, Integer dot) -> Integer?
        def kernel_index_of(state_id, production_id, dot)
          @kernel_cores.fetch(state_id).index([production_id, dot])
        end
      end
    end
  end
end
# steep:ignore:end

# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
