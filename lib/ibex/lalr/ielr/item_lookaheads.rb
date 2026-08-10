# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require_relative "bits"

module Ibex
  module LALR
    module IELR
      # Lazily derives the lookahead of a kernel item from predecessor states
      # and goto-follow sets.  Memoisation is important: predecessor paths can
      # share exponentially many suffixes in a real grammar.
      class ItemLookaheads
        # @rbs @memo: Hash[Integer, Integer]

        # @rbs (IR::Grammar grammar, GotoFollows goto_follows, Array[Array[item_core]] kernel_cores,
        #   Array[Array[Integer]] predecessors, ?start_states: Array[Integer]?) -> void
        def initialize(grammar, goto_follows, kernel_cores, predecessors, start_states: nil)
          @grammar = grammar
          @goto_follows = goto_follows
          @kernel_cores = kernel_cores
          @predecessors = predecessors
          @start_states = start_states || []
          @index = {}
          kernel_cores.each_with_index do |cores, state_id|
            cores.each_with_index { |core, kernel_index| @index[[state_id, core]] = kernel_index }
          end
          @memo = {}
        end

        # @rbs (Integer state_id, Integer kernel_index) -> Integer
        def fetch(state_id, kernel_index)
          key = [state_id, kernel_index]
          return @memo.fetch(key) if @memo.key?(key)

          @memo[key] = compute(state_id, kernel_index)
        end

        # @rbs () -> Integer
        def size
          @memo.length
        end

        private

        # @rbs (Integer state_id, Integer kernel_index) -> Integer
        def compute(state_id, kernel_index)
          production_id, dot = @kernel_cores.fetch(state_id).fetch(kernel_index)
          return start_seed(production_id) if production_id.negative? && dot.zero?
          return start_seed(production_id) if production_id.negative? && dot.positive?
          return 0 if dot.zero?
          return goto_follows_for(state_id, production_id) if dot == 1

          @predecessors.fetch(state_id).reduce(0) do |bits, previous|
            previous_index = @index[[previous, [production_id, dot - 1]]]
            previous_index ? bits | fetch(previous, previous_index) : bits
          end
        end

        # @rbs (Integer state_id, Integer production_id) -> Integer
        def goto_follows_for(state_id, production_id)
          lhs = @grammar.productions.fetch(production_id).lhs
          @predecessors.fetch(state_id).reduce(0) do |bits, previous|
            goto_id = @goto_follows.goto_for(previous, lhs)
            bits | (goto_id ? @goto_follows.goto_follows.fetch(goto_id) : 0)
          end
        end

        # @rbs (Integer production_id) -> Integer
        def start_seed(production_id)
          production_id.negative? ? 1 : 0
        end
      end
    end
  end
end
# steep:ignore:end
