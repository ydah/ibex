# frozen_string_literal: true

require "set"

module Ibex
  module LALR
    # Builds canonical LR(1) states and merges states with equal LR(0) cores.
    class Builder
      AUGMENTED_PRODUCTION = -1

      def initialize(grammar)
        @grammar = grammar
        @sets = Analysis::Sets.new(grammar)
        @productions_by_lhs = grammar.productions.group_by(&:lhs)
        @resolver = ConflictResolver.new(grammar)
      end

      def build
        canonical_states, canonical_transitions = canonical_collection
        merged_items, merged_transitions = merge_lalr(canonical_states, canonical_transitions)
        states = build_states(merged_items, merged_transitions)
        conflicts = states.flat_map(&:conflicts)
        summary = { sr: conflicts.count { |item| item[:type] == :shift_reduce },
                    rr: conflicts.count { |item| item[:type] == :reduce_reduce },
                    expected_sr: @grammar.expect,
                    expectation_met: conflicts.count { |item| item[:type] == :shift_reduce } == @grammar.expect }
        IR::Automaton.new(grammar: @grammar, states: states, conflict_summary: summary)
      end

      private

      def canonical_collection
        states = [closure(Set[[AUGMENTED_PRODUCTION, 0, 0]])]
        transitions = []
        indexes = { item_key(states.first) => 0 }
        cursor = 0
        while cursor < states.length
          transitions[cursor] = {}
          next_symbols(states[cursor]).each do |symbol_id|
            target = go_to(states[cursor], symbol_id)
            key = item_key(target)
            target_id = indexes[key] ||= begin
              states << target
              states.length - 1
            end
            transitions[cursor][symbol_id] = target_id
          end
          cursor += 1
        end
        [states, transitions]
      end

      def closure(seed)
        items = seed.dup
        queue = seed.to_a
        until queue.empty?
          production_id, dot, lookahead = queue.shift
          rhs = rhs_for(production_id)
          grammar_symbol = @grammar.symbol_by_id(rhs[dot])
          next unless grammar_symbol&.nonterminal?

          lookaheads = suffix_lookaheads(rhs[(dot + 1)..], lookahead)
          @productions_by_lhs.fetch(grammar_symbol.id, []).each do |production|
            lookaheads.each { |token_id| enqueue_item(items, queue, [production.id, 0, token_id]) }
          end
        end
        items
      end

      def suffix_lookaheads(suffix, inherited)
        bits = @sets.first_of_sequence(suffix)
        bits |= (1 << inherited) if @sets.sequence_nullable?(suffix)
        @grammar.terminals.filter_map { |terminal| terminal.id if bits.anybits?(1 << terminal.id) }
      end

      def enqueue_item(items, queue, item)
        return if items.include?(item)

        items << item
        queue << item
      end

      def next_symbols(items)
        items.filter_map { |production_id, dot, _lookahead| rhs_for(production_id)[dot] }.uniq.sort
      end

      def go_to(items, symbol_id)
        moved = items.filter_map do |production_id, dot, lookahead|
          [production_id, dot + 1, lookahead] if rhs_for(production_id)[dot] == symbol_id
        end
        closure(Set.new(moved))
      end

      def merge_lalr(states, transitions)
        groups = {}
        state_groups = states.map do |items|
          core = core_key(items)
          groups[core] ||= groups.length
        end
        merged = Array.new(groups.length) { Hash.new { |hash, key| hash[key] = Set.new } }
        states.each_with_index do |items, state_id|
          items.each { |production, dot, lookahead| merged[state_groups[state_id]][[production, dot]] << lookahead }
        end
        merged_transitions = Array.new(groups.length) { {} }
        transitions.each_with_index do |edges, state_id|
          edges.each { |symbol, target| merged_transitions[state_groups[state_id]][symbol] = state_groups[target] }
        end
        [merged, merged_transitions]
      end

      def build_states(merged_items, transitions)
        merged_items.each_with_index.map do |item_map, state_id|
          items = item_map.sort.map do |(production, dot), lookaheads|
            IR::AutomatonItem.new(production: production, dot: dot, lookaheads: lookaheads.to_a)
          end
          build_state(state_id, items, transitions[state_id])
        end
      end

      def build_state(state_id, items, transitions)
        candidates = Hash.new { |hash, key| hash[key] = [] }
        gotos = {}
        transitions.each do |symbol_id, target|
          grammar_symbol = @grammar.symbol_by_id(symbol_id)
          if grammar_symbol.terminal?
            candidates[symbol_id] << { type: :shift, state: target }
          else
            gotos[symbol_id] = target
          end
        end
        add_completed_actions(items, candidates)
        actions, conflicts = resolve_actions(candidates)
        IR::AutomatonState.new(id: state_id, items: items, transitions: transitions, actions: actions,
                               gotos: gotos, conflicts: conflicts)
      end

      def add_completed_actions(items, candidates)
        items.each do |item|
          next unless item.dot == rhs_for(item.production).length

          item.lookaheads.each do |lookahead|
            action = if item.production == AUGMENTED_PRODUCTION
                       { type: :accept }
                     else
                       { type: :reduce, production: item.production }
                     end
            candidates[lookahead] << action
          end
        end
      end

      def resolve_actions(candidates)
        actions = {}
        conflicts = []
        candidates.keys.sort.each do |token_id|
          action, found = @resolver.resolve(token_id, candidates[token_id])
          actions[token_id] = action
          conflicts.concat(found)
        end
        [actions, conflicts]
      end

      def rhs_for(production_id)
        return [@grammar.symbol(@grammar.start).id] if production_id == AUGMENTED_PRODUCTION

        @grammar.productions.fetch(production_id).rhs
      end

      def core_key(items)
        items.map { |production, dot, _lookahead| [production, dot] }.uniq.sort
      end

      def item_key(items)
        items.to_a.sort
      end
    end
  end
end
