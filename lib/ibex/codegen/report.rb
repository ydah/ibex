# frozen_string_literal: true

module Ibex
  module Codegen
    # Renders a human-readable state and conflict report from Automaton IR.
    module Report
      # @rbs!
      #   private def append_state: (
      #     Array[String] lines,
      #     IR::AutomatonState state,
      #     IR::Grammar grammar,
      #     Array[IR::counterexample] examples
      #   ) -> void
      #   private def self.append_state: (
      #     Array[String] lines,
      #     IR::AutomatonState state,
      #     IR::Grammar grammar,
      #     Array[IR::counterexample] examples
      #   ) -> void
      #   private def append_counterexample: (Array[String] lines, IR::counterexample example) -> void
      #   private def self.append_counterexample: (Array[String] lines, IR::counterexample example) -> void
      #   private def append_tree: (Array[String] lines, untyped tree, String indentation) -> void
      #   private def self.append_tree: (Array[String] lines, untyped tree, String indentation) -> void
      #   private def format_item: (IR::AutomatonItem item, IR::Grammar grammar) -> String
      #   private def self.format_item: (IR::AutomatonItem item, IR::Grammar grammar) -> String
      #   private def format_action: (IR::parser_action action) -> String
      #   private def self.format_action: (IR::parser_action action) -> String
      #   private def symbol_name: (IR::Grammar grammar, Integer id) -> String
      #   private def self.symbol_name: (IR::Grammar grammar, Integer id) -> String

      # @rbs (IR::Automaton automaton, ?max_tokens: Integer, ?max_configurations: Integer) -> String
      def render(automaton, max_tokens: LALR::Counterexample::DEFAULT_MAX_TOKENS,
                 max_configurations: LALR::Counterexample::DEFAULT_MAX_CONFIGURATIONS)
        grammar = automaton.grammar
        lines = ["Algorithm: #{automaton.algorithm}", "States: #{automaton.states.length}", ""]
        examples = LALR::Counterexample.new(
          automaton, max_tokens: max_tokens, max_configurations: max_configurations
        ).all.group_by { |example| example[:state] }
        automaton.states.each do |state|
          append_state(lines, state, grammar, examples.fetch(state.id, Array.new(0)))
        end
        summary = automaton.conflict_summary
        lines << "Conflicts: #{summary[:sr]} shift/reduce, #{summary[:rr]} reduce/reduce"
        "#{lines.join("\n")}\n"
      end
      module_function :render

      # @rbs skip
      private

      # @rbs skip
      def append_state(lines, state, grammar, examples)
        lines << "State #{state.id}"
        state.items.each { |item| lines << "  #{format_item(item, grammar)}" }
        state.actions.each do |token_id, action|
          lines << "  on #{symbol_name(grammar, token_id)}: #{format_action(action)}"
        end
        lines << "  default: #{format_action(state.default_action)}" if state.default_action
        state.gotos.each { |symbol_id, target| lines << "  goto #{symbol_name(grammar, symbol_id)}: #{target}" }
        state.conflicts.each { |conflict| lines << "  conflict: #{conflict.inspect}" }
        examples.each { |example| append_counterexample(lines, example) }
        lines << ""
      end

      # @rbs skip
      def append_counterexample(lines, example)
        label = example[:unifying] ? "unifying counterexample" : "nonunifying witness"
        sentence = example[:sentence].dup.insert(example[:lookahead_index], "•").join(" ")
        lines << "  #{label}: #{sentence}"
        example[:interpretations].each do |interpretation|
          lines << "    #{interpretation[:kind]} derivation:"
          append_tree(lines, interpretation[:tree], "      ")
        end
      end

      # @rbs skip
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

      # @rbs skip
      def format_item(item, grammar)
        if item.production == LALR::Builder::AUGMENTED_PRODUCTION
          rhs = [grammar.start]
          lhs = "$accept"
        else
          production = grammar.productions.fetch(item.production)
          rhs = production.rhs.map { |id| symbol_name(grammar, id) }
          lhs = symbol_name(grammar, production.lhs)
        end
        rhs = rhs.dup.insert(item.dot, "•")
        lookaheads = item.lookaheads.map { |id| symbol_name(grammar, id) }.join(", ")
        "#{lhs} -> #{rhs.join(' ')} [#{lookaheads}]"
      end

      # @rbs skip
      def format_action(action)
        case action[:type]
        when :shift then "shift #{action[:state]}"
        when :reduce then "reduce #{action[:production]}"
        else action[:type].to_s
        end
      end

      # @rbs skip
      def symbol_name(grammar, id)
        symbol = grammar.symbol_by_id(id) || raise(Ibex::Error, "missing grammar symbol id #{id}")
        symbol.name
      end
      module_function :append_state, :append_counterexample, :append_tree, :format_item, :format_action, :symbol_name

      class << self
        private :append_state, :append_counterexample, :append_tree, :format_item, :format_action, :symbol_name
      end
    end
  end
end
