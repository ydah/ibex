# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require "set"

module Ibex
  module LALR
    # Constructs only the LR(0) core collection.  Keeping this separate from
    # lookahead propagation makes the direct IELR phases reusable and gives
    # them a stable, canonical-free input representation.
    class LR0Collection
      AUGMENTED_PRODUCTION = -1 #: Integer

      # @rbs @grammar: IR::Grammar
      # @rbs @productions_by_lhs: Hash[Integer, Array[IR::Production]]
      # @rbs @starts: Array[String]
      # @rbs @augmented_rhs: Hash[Integer, Array[Integer]]
      # @rbs @production_rhs: Array[Array[Integer]]
      # @rbs @item_key_stride: Integer

      # @rbs (IR::Grammar grammar, ?starts: Array[String]?) -> void
      def initialize(grammar, starts: nil)
        @grammar = grammar
        @starts = (starts || grammar.starts).dup
        raise ArgumentError, "starts must be a nonempty subset of grammar starts" if
          @starts.empty? || (@starts - grammar.starts).any?

        @productions_by_lhs = grammar.productions.group_by(&:lhs)
        @production_rhs = grammar.productions.map(&:rhs).freeze
        @augmented_production_ids = @starts.map { |name| AUGMENTED_PRODUCTION - grammar.starts.index(name) }
        @augmented_rhs = @starts.each_with_index.to_h do |name, index|
          symbol = grammar.symbol(name) || raise(Ibex::Error, "missing start symbol #{name}")
          [@augmented_production_ids.fetch(index), [symbol.id].freeze]
        end.freeze
        @item_key_stride = [*@production_rhs, *@augmented_rhs.values].map(&:length).max.to_i + 1
      end

      # @rbs () -> [Array[core_set], transitions]
      def build
        states = @starts.map { |name| closure(Set[[augmented_production(@starts.index(name)), 0]]) }
        transitions = [] #: transitions
        indexes = {}
        states.each_with_index { |items, index| indexes[item_key(items)] = index }
        cursor = 0
        while cursor < states.length
          transitions[cursor] = {}
          shifted_kernels(states.fetch(cursor)).keys.sort.each do |symbol_id|
            target = closure(shifted_kernels(states.fetch(cursor)).fetch(symbol_id))
            target_id = indexes[item_key(target)] ||= begin
              states << target
              states.length - 1
            end
            transitions.fetch(cursor)[symbol_id] = target_id
          end
          cursor += 1
        end
        [states, transitions]
      end

      # @rbs (Integer index) -> Integer
      def augmented_production(index)
        @augmented_production_ids.fetch(index)
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        return @augmented_rhs.fetch(production_id) if production_id.negative?

        @production_rhs.fetch(production_id)
      end

      # @rbs (Integer production_id) -> Integer
      def lhs_for(production_id)
        return rhs_for(production_id).fetch(0) if production_id.negative?

        @grammar.productions.fetch(production_id).lhs
      end

      # @rbs (core_set items) -> Hash[Integer, core_set]
      def shifted_kernels(items)
        kernels = Hash.new { |hash, key| hash[key] = Set.new } #: Hash[Integer, core_set]
        items.each do |production_id, dot|
          symbol_id = rhs_for(production_id)[dot]
          kernels[symbol_id] << [production_id, dot + 1].freeze if symbol_id
        end
        kernels
      end

      private

      # @rbs (core_set seed) -> core_set
      def closure(seed)
        items = seed.dup
        queue = seed.to_a
        cursor = 0
        while cursor < queue.length
          production_id, dot = queue.fetch(cursor)
          cursor += 1
          symbol = @grammar.symbol_by_id(rhs_for(production_id)[dot])
          next unless symbol&.nonterminal?

          @productions_by_lhs.fetch(symbol.id, []).each do |production|
            item = [production.id, 0].freeze
            queue << item if items.add?(item)
          end
        end
        items
      end

      # @rbs (core_set items) -> Array[Integer]
      def item_key(items)
        items.map do |production_id, dot|
          ((production_id + @grammar.starts.length) * @item_key_stride) + dot
        end.sort
      end
    end
  end
end
# steep:ignore:end
