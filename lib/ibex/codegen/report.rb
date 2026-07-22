# frozen_string_literal: true

module Ibex
  module Codegen
    # Renders a human-readable state and conflict report from Automaton IR.
    module Report
      module_function

      def render(automaton, max_tokens: LALR::Counterexample::DEFAULT_MAX_TOKENS,
                 max_configurations: LALR::Counterexample::DEFAULT_MAX_CONFIGURATIONS)
        grammar = automaton.grammar
        lines = ["Algorithm: #{automaton.algorithm}", "States: #{automaton.states.length}", ""]
        examples = LALR::Counterexample.new(
          automaton, max_tokens: max_tokens, max_configurations: max_configurations
        ).all.group_by { |example| example[:state] }
        automaton.states.each do |state|
          append_state(lines, state, grammar, examples.fetch(state.id, []))
        end
        summary = automaton.conflict_summary
        lines << "Conflicts: #{summary[:sr]} shift/reduce, #{summary[:rr]} reduce/reduce"
        "#{lines.join("\n")}\n"
      end

      def append_state(lines, state, grammar, examples)
        lines << "State #{state.id}"
        state.items.each { |item| lines << "  #{format_item(item, grammar)}" }
        state.actions.each do |token_id, action|
          lines << "  on #{grammar.symbol_by_id(token_id).name}: #{format_action(action)}"
        end
        lines << "  default: #{format_action(state.default_action)}" if state.default_action
        state.gotos.each { |symbol_id, target| lines << "  goto #{grammar.symbol_by_id(symbol_id).name}: #{target}" }
        state.conflicts.each { |conflict| lines << "  conflict: #{conflict.inspect}" }
        examples.each { |example| append_counterexample(lines, example) }
        lines << ""
      end
      private_class_method :append_state

      def append_counterexample(lines, example)
        label = example[:unifying] ? "unifying counterexample" : "nonunifying witness"
        sentence = example[:sentence].dup.insert(example[:lookahead_index], "•").join(" ")
        lines << "  #{label}: #{sentence}"
        example[:interpretations].each do |interpretation|
          lines << "    #{interpretation[:kind]} derivation:"
          append_tree(lines, interpretation[:tree], "      ")
        end
      end
      private_class_method :append_counterexample

      def append_tree(lines, tree, indentation)
        unless tree.is_a?(Hash)
          lines << "#{indentation}#{tree}"
          return
        end

        symbol = tree[:symbol] || tree[:token]
        unless tree[:children]
          lines << "#{indentation}#{symbol}"
          return
        end

        production = tree[:production] ? " (production #{tree[:production]})" : ""
        lines << "#{indentation}#{symbol}#{production}"
        tree[:children].each { |child| append_tree(lines, child, "#{indentation}  ") }
      end
      private_class_method :append_tree

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
