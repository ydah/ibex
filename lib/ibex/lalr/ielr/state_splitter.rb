# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require "set"
require_relative "bits"
require_relative "split_state"
require_relative "annotator"
require_relative "split_stability"

module Ibex
  module LALR
    module IELR
      # Splits LR(0) isocores only where an inadequacy would change the
      # resolved action.  New states copy their transition arrays; no mutable
      # transition table is shared between isocores.
      class StateSplitter
        attr_reader :annotations #: Array[Array[Annotation]]
        attr_reader :states #: Array[SplitState]
        attr_reader :lalr_isocores #: Array[Integer]
        attr_reader :split_states #: Integer
        attr_reader :inadequacies #: Array[Array[Inadequacy]]
        attr_reader :split_stable_discarded #: Integer

        # @rbs (IR::Grammar grammar, Array[core_set] states, transitions transitions,
        #   Array[packed_items] items, GotoFollows goto_follows, ?resolver: ConflictResolver?) -> void
        # rubocop:disable Metrics/AbcSize -- initialization wires the phase tables once.
        def initialize(grammar, states, transitions, items, goto_follows, resolver: nil)
          @grammar = grammar
          @base_states = states
          @base_transitions = transitions
          @base_items = items
          @goto_follows = goto_follows
          @resolver = resolver || ConflictResolver.new(grammar)
          @kernel_cores = states.map { |state| kernel_items(state) }
          annotator = Annotator.new(grammar, states, transitions, items, goto_follows, resolver: @resolver)
          @annotations = annotator.build
          @inadequacies = annotator.inadequacies
          @split_stable_discarded = annotator.split_stable_discarded
          @item_lookaheads = annotator.item_lookaheads
          @states = states.each_with_index.map do |_state, state_id|
            SplitState.new(core: @kernel_cores.fetch(state_id),
                           transitions: transitions.fetch(state_id).sort_by(&:first).map(&:dup),
                           lalr_isocore: state_id)
          end
          @lalr_isocores = states.each_index.to_a
          @isocore_nexts = states.each_index.to_a
          @lookaheads_recomputed = Array.new(states.length, false)
          @lookahead_sets = states.each_with_index.map do |_state, state_id|
            @kernel_cores.fetch(state_id).each_index.map do |index|
              @item_lookaheads.fetch(state_id, index)
            end
          end
          @filters = {}
          @split_states = 0
        end
        # rubocop:enable Metrics/AbcSize

        # @rbs () -> [Array[packed_items], transitions]
        def build
          state_id = 0
          while state_id < @states.length
            @states.fetch(state_id).transitions.each_index do |index|
              target = @states.fetch(state_id).transitions.fetch(index).fetch(1)
              compute_state(state_id, target, index)
            end
            state_id += 1
          end
          [pack_items, packed_transitions]
        end

        private

        # @rbs (Integer from_id, Integer to_id, Integer transition_index) -> void
        def compute_state(from_id, to_id, transition_index)
          incoming = propagate_lookaheads(from_id, to_id)
          target = to_id
          found = false
          loop do
            if compatible?(target, incoming)
              found = true
              break
            end
            break if @isocore_nexts.fetch(target) == to_id

            target = @isocore_nexts.fetch(target)
          end

          if !found
            target = append_isocore(target, incoming)
          elsif !@lookaheads_recomputed.fetch(target)
            raise Ibex::Error, "IELR target changed before initial lookahead computation" unless target == to_id

            @lookahead_sets[target] = incoming
            @lookaheads_recomputed[target] = true
          else
            merge_lookaheads(target, incoming)
          end
          @states.fetch(from_id).transitions.fetch(transition_index)[1] = target
        end

        # @rbs (Integer from_id, Integer to_id) -> Array[Integer]
        def propagate_lookaheads(from_id, to_id)
          filters = lookahead_set_filters(to_id)
          @kernel_cores.fetch(to_id).each_with_index.map do |(production_id, dot), index|
            bits = if dot > 1
                     previous = kernel_index_of(from_id, production_id, dot - 1)
                     previous ? @lookahead_sets.fetch(from_id).fetch(previous) : 0
                   elsif dot == 1
                     compute_goto_follow_set(from_id, lhs_for(production_id))
                   else
                     raise Ibex::Error, "IELR transition produced a dot-zero kernel"
                   end
            bits & filters.fetch(index)
          end
        end

        # @rbs (Integer state_id, Integer nonterminal_id) -> Integer
        def compute_goto_follow_set(state_id, nonterminal_id)
          goto_id = @goto_follows.goto_for(@lalr_isocores.fetch(state_id), nonterminal_id)
          raise Ibex::Error, "missing GOTO for #{nonterminal_id} from #{state_id}" unless goto_id

          bits = @goto_follows.always_follows.fetch(goto_id)
          Bits.each_set_bit(@goto_follows.follow_kernel_items.fetch(goto_id)) do |index|
            bits |= @lookahead_sets.fetch(state_id).fetch(index)
          end
          bits
        end

        # @rbs (Integer state_id) -> Array[Integer]
        def lookahead_set_filters(state_id)
          core_id = @lalr_isocores.fetch(state_id)
          return @filters.fetch(core_id) if @filters.key?(core_id)

          filters = Array.new(@kernel_cores.fetch(core_id).length, 0)
          @annotations.fetch(core_id).each do |annotation|
            token_bit = 1 << annotation.inadequacy.token
            annotation.matrix.each do |row|
              next if row.nil?

              Bits.each_set_bit(row) { |index| filters[index] |= token_bit }
            end
          end
          @filters[core_id] = filters
        end

        # @rbs (Integer state_id, Array[Integer]) -> bool
        def compatible?(state_id, incoming)
          return true unless @lookaheads_recomputed.fetch(state_id)

          @annotations.fetch(@lalr_isocores.fetch(state_id)).all? do |annotation|
            current = dominant_contribution(annotation, @lookahead_sets.fetch(state_id))
            next true unless current

            candidate = dominant_contribution(annotation, incoming)
            !candidate || current == candidate
          end
        end

        # @rbs (Annotation, Array[Integer]) -> Object?
        def dominant_contribution(annotation, lookaheads)
          token_bit = 1 << annotation.inadequacy.token
          selected = annotation.inadequacy.contributions.each_index.select do |index|
            row = annotation.matrix.fetch(index)
            row.nil? || Bits.each_set_bit(row).any? { |kernel| lookaheads.fetch(kernel).anybits?(token_bit) }
          end
          return nil if selected.empty?

          contributions = selected.map { |index| annotation.inadequacy.contributions.fetch(index) }
          SplitStability.resolve(@resolver, annotation.inadequacy.token, contributions)
        end

        # @rbs (Integer after_id, Array[Integer]) -> Integer
        def append_isocore(after_id, lookaheads)
          source = @states.fetch(after_id)
          @states << SplitState.new(
            core: source.core.dup,
            transitions: source.transitions.map(&:dup),
            lalr_isocore: @lalr_isocores.fetch(after_id)
          )
          appended = @states.length - 1
          @lalr_isocores << @lalr_isocores.fetch(after_id)
          @isocore_nexts << @isocore_nexts.fetch(after_id)
          @isocore_nexts[after_id] = appended
          @lookaheads_recomputed << true
          @lookahead_sets << lookaheads
          @split_states += 1
          appended
        end

        # @rbs (Integer state_id, Array[Integer]) -> void
        def merge_lookaheads(state_id, incoming)
          changed = false
          incoming.each_with_index do |bits, index|
            added = bits & ~@lookahead_sets.fetch(state_id).fetch(index)
            next if added.zero?

            @lookahead_sets.fetch(state_id)[index] |= added
            changed = true
          end
          return unless changed

          @states.fetch(state_id).transitions.each_index do |index|
            target = @states.fetch(state_id).transitions.fetch(index).fetch(1)
            break unless @lookaheads_recomputed.fetch(target)

            compute_state(state_id, target, index)
          end
        end

        # @rbs () -> Array[packed_items]
        def pack_items
          @states.each_with_index.map do |state, state_id|
            packed = Hash.new { |hash, key| hash[key] = Set.new }
            @base_items.fetch(state.lalr_isocore).each do |core, values|
              packed[core].merge(values)
            end
            state.core.each_with_index do |core, index|
              packed[core] = Set.new(Bits.each_set_bit(@lookahead_sets.fetch(state_id).fetch(index)).to_a)
            end
            packed
          end
        end

        # @rbs () -> transitions
        def packed_transitions
          @states.map { |state| state.transitions.to_h { |symbol, target| [symbol, target] } }
        end

        # @rbs (core_set items) -> Array[item_core]
        def kernel_items(items)
          items.select { |production_id, dot| production_id.negative? || dot.positive? }.to_a.sort
        end

        # @rbs (Integer state_id, Integer production_id, Integer dot) -> Integer?
        def kernel_index_of(state_id, production_id, dot)
          @kernel_cores.fetch(@lalr_isocores.fetch(state_id)).index([production_id, dot])
        end

        # @rbs (Integer production_id) -> Integer
        def lhs_for(production_id)
          return @grammar.symbol(@grammar.starts.fetch(-production_id - 1)).id if production_id.negative?

          @grammar.productions.fetch(production_id).lhs
        end

        # @rbs (Integer production_id) -> Array[Integer]
        def rhs_for(production_id)
          return [lhs_for(production_id)] if production_id.negative?

          @grammar.productions.fetch(production_id).rhs
        end
      end
    end
  end
end
# steep:ignore:end
