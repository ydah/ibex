# frozen_string_literal: true

module Ibex
  module LALR
    # Produces shortest-path conflict witnesses using Automaton IR only.
    class Counterexample
      def initialize(automaton)
        @automaton = automaton
        @grammar = automaton.grammar
        @shortest_yields = compute_shortest_yields
      end

      def all
        @automaton.states.flat_map do |state|
          state.conflicts.map { |conflict| build_example(state, conflict) }
        end
      end

      private

      def build_example(state, conflict)
        path = shortest_state_path(state.id)
        lookahead = @grammar.symbol(conflict[:symbol])
        terminal_ids = path.flat_map { |symbol_id| @shortest_yields[symbol_id] || [] }
        terminal_ids << lookahead.id if lookahead
        { state: state.id, type: conflict[:type], symbol_path: names(path), sentence: names(terminal_ids),
          interpretations: interpretations(conflict) }
      end

      def shortest_state_path(target)
        queue = [[0, []]]
        visited = { 0 => true }
        until queue.empty?
          state_id, path = queue.shift
          return path if state_id == target

          @automaton.states.fetch(state_id).transitions.sort.each do |symbol_id, next_state|
            next if visited[next_state]

            visited[next_state] = true
            queue << [next_state, path + [symbol_id]]
          end
        end
        []
      end

      def compute_shortest_yields
        yields = @grammar.terminals.to_h { |terminal| [terminal.id, [terminal.id]] }
        loop do
          changed = false
          @grammar.productions.each do |production|
            candidate = production.rhs.flat_map { |id| yields[id] || [] }
            next unless production.rhs.all? { |id| yields.key?(id) }
            next unless better_yield?(candidate, yields[production.lhs])

            yields[production.lhs] = candidate
            changed = true
          end
          return yields unless changed
        end
      end

      def better_yield?(candidate, current)
        return true unless current
        return candidate.length < current.length if candidate.length != current.length

        (names(candidate) <=> names(current)).negative?
      end

      def interpretations(conflict)
        case conflict[:type]
        when :shift_reduce
          [shift_interpretation(conflict), reduce_interpretation(conflict[:reduce])]
        when :reduce_reduce
          conflict[:reductions].map { |production_id| reduce_interpretation(production_id) }
        else []
        end
      end

      def shift_interpretation(conflict)
        { kind: :shift, state: conflict[:shift_to], tree: { token: conflict[:symbol] } }
      end

      def reduce_interpretation(production_id)
        production = @grammar.productions.fetch(production_id)
        lhs = @grammar.symbol_by_id(production.lhs).name
        rhs = names(production.rhs)
        { kind: :reduce, production: production_id, tree: { symbol: lhs, children: rhs } }
      end

      def names(symbol_ids)
        symbol_ids.map { |id| @grammar.symbol_by_id(id).name }
      end
    end
  end
end
