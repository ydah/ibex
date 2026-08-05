# frozen_string_literal: true

require_relative "../lalr"
require_relative "symbol_labels"

module Ibex
  module Codegen
    # Renders a human-readable state and conflict report from Automaton IR.
    module Report
      # @rbs!
      #   private def append_state: (
      #     Array[String] lines,
      #     IR::AutomatonState state,
      #     IR::Grammar grammar,
      #     Array[LALR::search_counterexample] examples,
      #     Hash[Integer, String] labels
      #   ) -> void
      #   private def self.append_state: (
      #     Array[String] lines,
      #     IR::AutomatonState state,
      #     IR::Grammar grammar,
      #     Array[LALR::search_counterexample] examples,
      #     Hash[Integer, String] labels
      #   ) -> void
      #   private def append_counterexample: (Array[String] lines, LALR::search_counterexample example,
      #     IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> void
      #   private def self.append_counterexample: (Array[String] lines, LALR::search_counterexample example,
      #     IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> void
      #   private def append_tree: (Array[String] lines, untyped tree, String indentation, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> void
      #   private def self.append_tree: (Array[String] lines, untyped tree, String indentation, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> void
      #   private def format_item: (IR::AutomatonItem item, IR::Grammar grammar, Hash[Integer, String] labels) -> String
      #   private def self.format_item: (IR::AutomatonItem item, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> String
      #   private def format_action: (IR::parser_action action) -> String
      #   private def self.format_action: (IR::parser_action action) -> String
      #   private def symbol_name: (Hash[Integer, String] labels, Integer id) -> String
      #   private def self.symbol_name: (Hash[Integer, String] labels, Integer id) -> String
      #   private def tree_label: (IR::Grammar grammar, Hash[Integer, String] labels, untyped value) -> untyped
      #   private def self.tree_label: (IR::Grammar grammar, Hash[Integer, String] labels, untyped value) -> untyped
      #   private def display_conflict: (IR::conflict conflict, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> Hash[Symbol, untyped]
      #   private def self.display_conflict: (IR::conflict conflict, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> Hash[Symbol, untyped]
      #   private def format_value: (untyped value) -> String
      #   private def self.format_value: (untyped value) -> String

      # @rbs (IR::Automaton automaton, ?max_tokens: Integer, ?max_configurations: Integer) -> String
      def render(automaton, max_tokens: LALR::Counterexample::DEFAULT_MAX_TOKENS,
                 max_configurations: LALR::Counterexample::DEFAULT_MAX_CONFIGURATIONS)
        grammar = automaton.grammar
        labels = SymbolLabels.build(grammar)
        entries = automaton.entry_states.map { |name, state| "#{name}=#{state}" }.join(", ")
        lines = ["Algorithm: #{automaton.algorithm}", "States: #{automaton.states.length}"]
        lines << "Entries: #{entries}" if automaton.entry_states.length > 1
        lines << ""
        examples = LALR::Counterexample.new(
          automaton, max_tokens: max_tokens, max_configurations: max_configurations
        ).all.group_by { |example| example[:state] }
        automaton.states.each do |state|
          append_state(lines, state, grammar, examples.fetch(state.id, Array.new(0)), labels)
        end
        summary = automaton.conflict_summary
        lines << "Conflicts: #{summary[:sr]} shift/reduce, #{summary[:rr]} reduce/reduce"
        "#{lines.join("\n")}\n"
      end
      module_function :render

      # @rbs skip
      private

      # @rbs skip
      def append_state(lines, state, grammar, examples, labels)
        lines << "State #{state.id}"
        state.items.each { |item| lines << "  #{format_item(item, grammar, labels)}" }
        state.actions.each do |token_id, action|
          lines << "  on #{symbol_name(labels, token_id)}: #{format_action(action)}"
        end
        lines << "  default: #{format_action(state.default_action)}" if state.default_action
        state.gotos.each { |symbol_id, target| lines << "  goto #{symbol_name(labels, symbol_id)}: #{target}" }
        state.conflicts.each do |conflict|
          lines << "  conflict: #{format_value(display_conflict(conflict, grammar, labels))}"
        end
        examples.each { |example| append_counterexample(lines, example, grammar, labels) }
        lines << ""
      end

      # @rbs skip
      def append_counterexample(lines, example, grammar, labels)
        label = if example[:unifying]
                  "unifying counterexample"
                elsif example[:inconclusive]
                  "inconclusive reachability witness"
                else
                  "nonunifying witness"
                end
        sentence = example[:sentence].map { |name| tree_label(grammar, labels, name) }
        sentence = sentence.dup.insert(example[:lookahead_index], "•").join(" ")
        lines << "  #{label}: #{sentence}"
        if example[:inconclusive]
          search = example.fetch(:search)
          lines << "    search exhausted after #{search.fetch(:explored)} configurations; no classification was made"
        end
        example[:interpretations].each do |interpretation|
          lines << "    #{interpretation[:kind]} derivation:"
          append_tree(lines, interpretation[:tree], "      ", grammar, labels)
        end
      end

      # @rbs skip
      def append_tree(lines, tree, indentation, grammar, labels)
        unless tree.is_a?(Hash)
          lines << "#{indentation}#{tree_label(grammar, labels, tree)}"
          return
        end

        symbol = tree_label(grammar, labels, tree[:symbol] || tree[:token])
        unless tree[:children]
          lines << "#{indentation}#{symbol}"
          return
        end

        production = tree[:production] ? " (production #{tree[:production]})" : ""
        lines << "#{indentation}#{symbol}#{production}"
        tree[:children].each { |child| append_tree(lines, child, "#{indentation}  ", grammar, labels) }
      end

      # @rbs skip
      def format_item(item, grammar, labels)
        if item.production == LALR::Builder::AUGMENTED_PRODUCTION
          start = grammar.symbol(grammar.start)
          rhs = [grammar.starts.one? && start ? symbol_name(labels, start.id) : "<entry>"]
          lhs = "$accept"
        else
          production = grammar.productions.fetch(item.production)
          rhs = production.rhs.map { |id| symbol_name(labels, id) }
          lhs = symbol_name(labels, production.lhs)
        end
        rhs = rhs.dup.insert(item.dot, "•")
        lookaheads = item.lookaheads.map { |id| symbol_name(labels, id) }.join(", ")
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
      def symbol_name(labels, id)
        labels.fetch(id) { raise Ibex::Error, "missing grammar symbol id #{id}" }
      end

      # @rbs skip
      def tree_label(grammar, labels, value)
        symbol = grammar.symbol(value.to_s)
        symbol ? symbol_name(labels, symbol.id) : value
      end

      # @rbs skip
      def display_conflict(conflict, grammar, labels)
        symbol = grammar.symbol(conflict[:symbol])
        return conflict unless symbol

        conflict.merge(symbol: symbol_name(labels, symbol.id))
      end

      # Keep reports byte-identical across Ruby versions whose Hash#inspect
      # formatting differs for symbol keys.
      # @rbs skip
      def format_value(value)
        case value
        when Hash
          entries = value.map do |key, item|
            label = key.is_a?(Symbol) ? "#{key}:" : "#{format_value(key)} =>"
            "#{label} #{format_value(item)}"
          end
          "{#{entries.join(', ')}}"
        when Array
          "[#{value.map { |item| format_value(item) }.join(', ')}]"
        else
          value.inspect
        end
      end
      module_function :append_state, :append_counterexample, :append_tree, :format_item, :format_action, :symbol_name,
                      :tree_label, :display_conflict, :format_value

      class << self
        private :append_state, :append_counterexample, :append_tree, :format_item, :format_action, :symbol_name,
                :tree_label, :display_conflict, :format_value
      end
    end
  end
end
