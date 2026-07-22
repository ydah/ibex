# frozen_string_literal: true

module Ibex
  module Codegen
    # Renders a human-readable state and conflict report from Automaton IR.
    module Report
      module_function

      def render(automaton)
        grammar = automaton.grammar
        lines = ["Algorithm: #{automaton.algorithm}", "States: #{automaton.states.length}", ""]
        automaton.states.each do |state|
          lines << "State #{state.id}"
          state.items.each { |item| lines << "  #{format_item(item, grammar)}" }
          state.actions.each do |token_id, action|
            lines << "  on #{grammar.symbol_by_id(token_id).name}: #{format_action(action)}"
          end
          state.gotos.each { |symbol_id, target| lines << "  goto #{grammar.symbol_by_id(symbol_id).name}: #{target}" }
          state.conflicts.each { |conflict| lines << "  conflict: #{conflict.inspect}" }
          lines << ""
        end
        summary = automaton.conflict_summary
        lines << "Conflicts: #{summary[:sr]} shift/reduce, #{summary[:rr]} reduce/reduce"
        "#{lines.join("\n")}\n"
      end

      def format_item(item, grammar)
        if item.production == LALR::Builder::AUGMENTED_PRODUCTION
          rhs = [grammar.start]
          lhs = "$accept"
        else
          production = grammar.productions.fetch(item.production)
          rhs = production.rhs.map { |id| grammar.symbol_by_id(id).name }
          lhs = grammar.symbol_by_id(production.lhs).name
        end
        rhs = rhs.dup.insert(item.dot, "•")
        lookaheads = item.lookaheads.map { |id| grammar.symbol_by_id(id).name }.join(", ")
        "#{lhs} -> #{rhs.join(' ')} [#{lookaheads}]"
      end
      private_class_method :format_item

      def format_action(action)
        case action[:type]
        when :shift then "shift #{action[:state]}"
        when :reduce then "reduce #{action[:production]}"
        else action[:type].to_s
        end
      end
      private_class_method :format_action
    end
  end
end
