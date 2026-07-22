# frozen_string_literal: true

module Ibex
  module LALR
    # Applies yacc-compatible precedence and ordering rules to action candidates.
    class ConflictResolver
      def initialize(grammar)
        @grammar = grammar
      end

      def resolve(token_id, candidates)
        actions = candidates.uniq
        return [actions.first, []] if actions.length <= 1

        accept = actions.find { |action| action[:type] == :accept }
        return [accept, []] if accept

        shift = actions.find { |action| action[:type] == :shift }
        reductions = actions.select { |action| action[:type] == :reduce }.sort_by { |action| action[:production] }
        chosen_reduce, conflicts = resolve_reductions(token_id, reductions)
        return [chosen_reduce, conflicts] unless shift
        return [shift, conflicts] unless chosen_reduce

        chosen, conflict = resolve_shift_reduce(token_id, shift, chosen_reduce)
        [chosen, conflicts << conflict]
      end

      private

      def resolve_reductions(token_id, reductions)
        return [nil, []] if reductions.empty?
        return [reductions.first, []] if reductions.length == 1

        chosen = reductions.first
        conflict = { type: :reduce_reduce, symbol: token_name(token_id),
                     reductions: reductions.map { |action| action[:production] },
                     resolution: { by: :definition_order, chose: chosen[:production] } }
        [chosen, [conflict]]
      end

      def resolve_shift_reduce(token_id, shift, reduction)
        token_precedence = @grammar.symbol_by_id(token_id).precedence
        production_precedence = precedence_for_production(reduction[:production])
        chosen, resolution = precedence_choice(shift, reduction, token_precedence, production_precedence)
        conflict = { type: :shift_reduce, symbol: token_name(token_id), shift_to: shift[:state],
                     reduce: reduction[:production], resolution: resolution }
        [chosen, conflict]
      end

      def precedence_choice(shift, reduction, token_precedence, production_precedence)
        return [shift, { by: :default_shift, chose: :shift }] unless token_precedence && production_precedence

        comparison = token_precedence[:level] <=> production_precedence[:level]
        return [shift, { by: :precedence, chose: :shift }] if comparison.positive?
        return [reduction, { by: :precedence, chose: :reduce }] if comparison.negative?

        associativity_choice(shift, reduction, token_precedence[:associativity])
      end

      def associativity_choice(shift, reduction, associativity)
        case associativity.to_sym
        when :left then [reduction, { by: :associativity, associativity: :left, chose: :reduce }]
        when :right then [shift, { by: :associativity, associativity: :right, chose: :shift }]
        when :nonassoc then [{ type: :error }, { by: :associativity, associativity: :nonassoc, chose: :error }]
        end
      end

      def precedence_for_production(production_id)
        production = @grammar.productions.fetch(production_id)
        return @grammar.symbol_by_id(production.precedence_override).precedence if production.precedence_override

        production.rhs.reverse_each do |symbol_id|
          grammar_symbol = @grammar.symbol_by_id(symbol_id)
          return grammar_symbol.precedence if grammar_symbol.terminal? && grammar_symbol.precedence
        end
        nil
      end

      def token_name(token_id)
        @grammar.symbol_by_id(token_id).name
      end
    end
  end
end
