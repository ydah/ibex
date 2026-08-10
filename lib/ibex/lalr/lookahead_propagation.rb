# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require "set"

module Ibex
  module LALR
    # Recomputes item lookaheads on an already-built LR(0) automaton.  This is
    # Phase 4 of direct IELR and is also useful as an independent cross-check
    # for DirectLookaheads.
    class LookaheadPropagation
      EMPTY = Array.new(0).freeze #: Array[Integer]

      attr_reader :propagation_edge_count #: Integer

      # @rbs (IR::Grammar grammar, Analysis::Sets sets, Array[core_set] states, transitions transitions,
      #   seeds: Array[[Integer, item_core, Integer]]) -> Array[packed_items]
      def initialize(grammar, sets, states, transitions, seeds:)
        @grammar = grammar
        @sets = sets
        @states = states
        @transitions = transitions
        @seeds = seeds
        @productions_by_lhs = grammar.productions.group_by(&:lhs)
      end

      # @rbs () -> Array[packed_items]
      def build
        lookaheads = @states.map { |items| items.to_h { |item| [item, Set.new] } }
        edges = Hash.new { |hash, key| hash[key] = [] }
        @states.each_with_index do |items, state_id|
          items.each do |production_id, dot|
            add_transition(edges, state_id, production_id, dot)
            add_closure(edges, lookaheads, state_id, production_id, dot)
          end
        end
        @seeds.each { |state_id, item, token| lookaheads.fetch(state_id).fetch(item) << token }
        @propagation_edge_count = edges.values.sum(&:length)
        propagate(lookaheads, edges)
        lookaheads
      end

      private

      # @rbs (Hash[Object, Array[Object]], Integer, Integer, Integer) -> void
      def add_transition(edges, state_id, production_id, dot)
        symbol_id = rhs_for(production_id)[dot]
        return unless symbol_id

        target = @transitions.fetch(state_id).fetch(symbol_id)
        edges[[state_id, production_id, dot]] << [target, production_id, dot + 1]
      end

      # @rbs (Hash[Object, Array[Object]], Array[packed_items], Integer, Integer, Integer) -> void
      def add_closure(edges, lookaheads, state_id, production_id, dot)
        rhs = rhs_for(production_id)
        symbol = @grammar.symbol_by_id(rhs[dot])
        return unless symbol&.nonterminal?

        suffix = rhs.drop(dot + 1)
        spontaneous = terminal_ids(@sets.first_of_sequence(suffix))
        @productions_by_lhs.fetch(symbol.id, []).each do |production|
          item = [production.id, 0].freeze
          lookaheads.fetch(state_id).fetch(item).merge(spontaneous)
          edges[[state_id, production_id, dot]] << [state_id, production.id, 0] if
            @sets.sequence_nullable?(suffix)
        end
      end

      # @rbs (Array[packed_items], Hash[Object, Array[Object]]) -> void
      def propagate(lookaheads, edges)
        queue = @seeds.map { |state_id, (production_id, dot), _token| [state_id, production_id, dot] }
        queue.concat(lookaheads.each_with_index.flat_map do |items, state_id|
          items.filter_map { |(production_id, dot), values| [state_id, production_id, dot] unless values.empty? }
        end)
        queued = queue.to_h { |node| [node, true] }
        cursor = 0
        while cursor < queue.length
          source = queue.fetch(cursor)
          cursor += 1
          queued.delete(source)
          source_set = lookaheads.fetch(source[0]).fetch([source[1], source[2]])
          edges.fetch(source, EMPTY).each do |target|
            target_set = lookaheads.fetch(target[0]).fetch([target[1], target[2]])
            previous_size = target_set.size
            target_set.merge(source_set)
            next if target_set.size == previous_size || queued[target]

            queue << target
            queued[target] = true
          end
        end
      end

      # @rbs (Integer bits) -> Array[Integer]
      def terminal_ids(bits)
        @grammar.terminals.filter_map { |terminal| terminal.id if bits.anybits?(1 << terminal.id) }
      end

      # @rbs (Integer production_id) -> Array[Integer]
      def rhs_for(production_id)
        return [@grammar.symbol(@grammar.starts.fetch(-production_id - 1)).id] if production_id.negative?

        @grammar.productions.fetch(production_id).rhs
      end
    end
  end
end
# steep:ignore:end
