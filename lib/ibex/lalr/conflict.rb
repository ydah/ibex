# frozen_string_literal: true

module Ibex
  module LALR
    # Applies yacc-compatible precedence and ordering rules to action candidates.
    class ConflictResolver
      # @rbs (IR::Grammar grammar) -> void
      def initialize(grammar)
        @grammar = grammar
      end

      # @rbs (Integer token_id, Array[IR::parser_action] candidates) -> [IR::parser_action?, Array[IR::conflict]]
      def resolve(token_id, candidates)
        actions = candidates.uniq
        return [actions.first, Array.new(0)] if actions.length <= 1

        accept = actions.find { |action| action[:type] == :accept }
        return [accept, Array.new(0)] if accept

        shift = actions.find { |action| action[:type] == :shift } #: IR::shift_action?
        reductions = reduction_actions(actions)
        chosen_reduce, conflicts = resolve_reductions(token_id, reductions)
        all_conflicts = widen_conflicts(conflicts)
        return [chosen_reduce, all_conflicts] unless shift
        return [shift, all_conflicts] unless chosen_reduce

        chosen, conflict = resolve_shift_reduce(token_id, shift, chosen_reduce)
        [chosen, all_conflicts << conflict]
      end

      private

      # @rbs (Array[IR::parser_action] actions) -> Array[IR::reduce_action]
      def reduction_actions(actions)
        reductions = [] #: Array[IR::reduce_action]
        actions.each do |action|
          next unless action[:type] == :reduce

          reduction = action #: IR::reduce_action
          reductions << reduction
        end
        reductions.sort_by { |action| action[:production] }
      end

      # @rbs (Array[IR::reduce_reduce_conflict] conflicts) -> Array[IR::conflict]
      def widen_conflicts(conflicts)
        conflicts.map(&:itself) #: Array[IR::conflict]
      end

      # @rbs (Integer token_id, Array[IR::reduce_action] reductions) ->
      #   [IR::reduce_action?, Array[IR::reduce_reduce_conflict]]
      def resolve_reductions(token_id, reductions)
        return [nil, Array.new(0)] if reductions.empty?
        return [reductions.first, Array.new(0)] if reductions.length == 1

        chosen = reductions.first
        conflict = { type: :reduce_reduce, symbol: token_name(token_id),
                     reductions: reductions.map { |action| action[:production] },
                     resolution: { by: :definition_order, chose: chosen[:production] } } #: IR::reduce_reduce_conflict
        [chosen, [conflict]]
      end

      # @rbs (Integer token_id, IR::shift_action shift, IR::reduce_action reduction) ->
      #   [IR::parser_action, IR::shift_reduce_conflict]
      def resolve_shift_reduce(token_id, shift, reduction)
        token_precedence = required_symbol_by_id(token_id).precedence
        production_precedence = precedence_for_production(reduction[:production])
        chosen, resolution = precedence_choice(shift, reduction, token_precedence, production_precedence)
        conflict = { type: :shift_reduce, symbol: token_name(token_id), shift_to: shift[:state],
                     reduce: reduction[:production], resolution: resolution } #: IR::shift_reduce_conflict
        [chosen, conflict]
      end

      # @rbs (IR::shift_action shift, IR::reduce_action reduction, IR::precedence? token_precedence,
      #   IR::precedence? production_precedence) -> [IR::parser_action, IR::conflict_resolution]
      def precedence_choice(shift, reduction, token_precedence, production_precedence)
        return [shift, { by: :default_shift, chose: :shift }] unless token_precedence && production_precedence

        comparison = token_precedence[:level] <=> production_precedence[:level]
        return [shift, { by: :precedence, chose: :shift }] if comparison.positive?
        return [reduction, { by: :precedence, chose: :reduce }] if comparison.negative?

        associativity_choice(shift, reduction, token_precedence[:associativity])
      end

      # @rbs (IR::shift_action shift, IR::reduce_action reduction, Symbol associativity) ->
      #   [IR::parser_action, IR::conflict_resolution]
      def associativity_choice(shift, reduction, associativity)
        case associativity.to_sym
        when :left then [reduction, { by: :associativity, associativity: :left, chose: :reduce }]
        when :right then [shift, { by: :associativity, associativity: :right, chose: :shift }]
        when :nonassoc then [{ type: :error }, { by: :associativity, associativity: :nonassoc, chose: :error }]
        else raise Ibex::Error, "unknown associativity #{associativity.inspect}"
        end
      end

      # @rbs (Integer production_id) -> IR::precedence?
      def precedence_for_production(production_id)
        production = @grammar.productions.fetch(production_id)
        return required_symbol_by_id(production.precedence_override).precedence if production.precedence_override

        production.rhs.reverse_each do |symbol_id|
          grammar_symbol = required_symbol_by_id(symbol_id)
          return grammar_symbol.precedence if grammar_symbol.terminal? && grammar_symbol.precedence
        end
        nil
      end

      # @rbs (Integer token_id) -> String
      def token_name(token_id)
        required_symbol_by_id(token_id).name
      end

      # @rbs (Integer id) -> IR::GrammarSymbol
      def required_symbol_by_id(id)
        @grammar.symbol_by_id(id) || raise(Ibex::Error, "missing grammar symbol id #{id}")
      end
    end
  end
end
