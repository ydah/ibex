# frozen_string_literal: true

module Ibex
  module Codegen
    # @rbs!
    #   type explain_entry = {
    #     state: IR::AutomatonState,
    #     conflict: IR::conflict,
    #     example: IR::counterexample
    #   }

    # Renders a selected conflict explanation from Automaton IR and counterexamples.
    # rubocop:disable Metrics/ClassLength -- inline contracts and two stable output formats stay near selection policy.
    class Explain
      SCHEMA_VERSION = 1 #: Integer

      # @rbs (IR::Automaton automaton, ?state: Integer?, ?token: String?, ?max_tokens: Integer,
      #   ?max_configurations: Integer) -> void
      def initialize(automaton, state: nil, token: nil, max_tokens: LALR::Counterexample::DEFAULT_MAX_TOKENS,
                     max_configurations: LALR::Counterexample::DEFAULT_MAX_CONFIGURATIONS)
        @automaton = automaton
        @grammar = automaton.grammar
        @state_selector = state
        @token_query = token
        @max_tokens = max_tokens
        @max_configurations = max_configurations
        @labels = SymbolLabels.build(@grammar)
        @token_selector = resolve_token(token)
        validate_state!
        @entries = select_entries
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        unifying = @entries.count { |entry| entry.fetch(:example).fetch(:unifying) }
        {
          ibex_explain: "conflicts",
          schema_version: SCHEMA_VERSION,
          algorithm: @automaton.algorithm,
          selectors: {
            state: @state_selector,
            token: @token_selector && token_reference(@token_selector, query: @token_query)
          },
          search: { max_tokens: @max_tokens, max_configurations: @max_configurations },
          summary: {
            matched_conflicts: @entries.length,
            unifying_counterexamples: unifying,
            nonunifying_witnesses: @entries.length - unifying
          },
          conflicts: @entries.map { |entry| conflict_document(entry) }
        }
      end

      # @rbs () -> String
      def render_text
        lines = [
          "Ibex conflict explanation v#{SCHEMA_VERSION}",
          "Algorithm: #{@automaton.algorithm}",
          "State selector: #{@state_selector || 'all'}",
          "Token selector: #{@token_selector ? token_label(@token_selector, query: @token_query) : 'all'}",
          "Search budget: #{@max_tokens} tokens, #{@max_configurations} configurations",
          "Matched conflicts: #{@entries.length}",
          ""
        ]
        if @entries.empty?
          lines << "No conflicts matched the selectors."
        else
          @entries.each_with_index { |entry, index| append_conflict(lines, entry, index + 1) }
        end
        "#{lines.join("\n")}\n"
      end

      private

      # @rbs (String? query) -> IR::GrammarSymbol?
      def resolve_token(query)
        return unless query

        canonical = @grammar.terminals.find { |symbol| symbol.name == query }
        return canonical if canonical

        displayed = @grammar.terminals.select { |symbol| symbol.display_name == query }
        return displayed.first if displayed.one?

        if displayed.length > 1
          names = displayed.map(&:name).sort.join(", ")
          raise Ibex::Error, "(cli):1:1: token display name #{query.inspect} is ambiguous; use one of: #{names}"
        end

        raise Ibex::Error,
              "(cli):1:1: unknown token #{query.inspect}; use a grammar token name or an exact display name"
      end

      # @rbs () -> void
      def validate_state!
        return unless @state_selector
        return if @state_selector >= 0 && @automaton.states.any? { |state| state.id == @state_selector }

        raise Ibex::Error, "(cli):1:1: unknown automaton state #{@state_selector}"
      end

      # @rbs () -> Array[explain_entry]
      def select_entries
        examples = LALR::Counterexample.new(
          @automaton, max_tokens: @max_tokens, max_configurations: @max_configurations
        ).all
        index = 0
        @automaton.states.flat_map do |state|
          state.conflicts.filter_map do |conflict|
            example = examples.fetch(index)
            index += 1
            next if @state_selector && state.id != @state_selector
            next if @token_selector && conflict[:symbol] != @token_selector.name

            { state: state, conflict: conflict, example: example }
          end
        end
      end

      # @rbs (explain_entry entry) -> Hash[Symbol, untyped]
      def conflict_document(entry)
        state = entry.fetch(:state)
        conflict = entry.fetch(:conflict)
        example = entry.fetch(:example)
        {
          state: state.id,
          type: conflict.fetch(:type).to_s,
          token: symbol_reference(conflict.fetch(:symbol)),
          alternatives: conflict_alternatives(conflict),
          resolution: string_values(conflict.fetch(:resolution)),
          witness: {
            kind: example.fetch(:unifying) ? "unifying_counterexample" : "nonunifying_witness",
            sentence: example.fetch(:sentence).map { |name| symbol_reference(name) },
            lookahead_index: example.fetch(:lookahead_index),
            symbol_path: example.fetch(:symbol_path).map { |name| symbol_reference(name) },
            interpretations: example.fetch(:interpretations).map { |item| interpretation_document(item) }
          }
        }
      end

      # @rbs (IR::conflict conflict) -> Array[Hash[Symbol, untyped]]
      def conflict_alternatives(conflict)
        case conflict[:type]
        when :shift_reduce
          [{ kind: "shift", state: conflict.fetch(:shift_to) },
           { kind: "reduce", production: conflict.fetch(:reduce) }]
        when :reduce_reduce
          reduce_reduce = conflict #: IR::reduce_reduce_conflict
          reduce_reduce[:reductions].map { |production| { kind: "reduce", production: production } }
        else
          []
        end
      end

      # @rbs (IR::interpretation interpretation) -> Hash[Symbol, untyped]
      def interpretation_document(interpretation)
        value = { kind: interpretation.fetch(:kind).to_s,
                  tree: tree_document(interpretation.fetch(:tree)) } #: Hash[Symbol, untyped]
        value[:state] = interpretation[:state] if interpretation.key?(:state)
        value[:production] = interpretation[:production] if interpretation.key?(:production)
        value
      end

      # @rbs (untyped tree) -> untyped
      def tree_document(tree)
        return symbol_reference(tree.to_s) unless tree.is_a?(Hash)

        value = {} #: Hash[Symbol, untyped]
        value[:symbol] = symbol_reference(tree[:symbol]) if tree[:symbol]
        value[:token] = symbol_reference(tree[:token]) if tree[:token]
        value[:production] = tree[:production] if tree[:production]
        value[:children] = tree[:children].map { |child| tree_document(child) } if tree[:children]
        value
      end

      # @rbs (Hash[Symbol, untyped] value) -> Hash[Symbol, untyped]
      def string_values(value)
        value.transform_values { |item| item.is_a?(Symbol) ? item.to_s : item }
      end

      # @rbs (String name) -> Hash[Symbol, untyped]
      def symbol_reference(name)
        symbol = @grammar.symbol(name)
        return { name: name, display_name: nil, label: name } unless symbol

        token_reference(symbol)
      end

      # @rbs (IR::GrammarSymbol symbol, ?query: String?) -> Hash[Symbol, untyped]
      def token_reference(symbol, query: nil)
        value = { name: symbol.name, display_name: symbol.display_name,
                  label: @labels.fetch(symbol.id, symbol.name) } #: Hash[Symbol, untyped]
        value[:query] = query if query
        value
      end

      # @rbs (Array[String] lines, explain_entry entry, Integer number) -> void
      def append_conflict(lines, entry, number)
        state = entry.fetch(:state)
        conflict = entry.fetch(:conflict)
        example = entry.fetch(:example)
        token = @grammar.symbol(conflict.fetch(:symbol))
        token_text = token ? token_label(token) : conflict.fetch(:symbol)
        type = conflict.fetch(:type).to_s.tr("_", "/")
        lines << "Conflict #{number}: state #{state.id}, #{type}, token #{token_text}"
        append_witness_steps(lines, state, conflict, example)
        append_interpretations(lines, example)
        unless example.fetch(:unifying)
          lines << "  The search found no shared sentence within the configured budget; this witness is deterministic."
        end
        lines << ""
      end

      # @rbs (Array[String] lines, IR::AutomatonState state, IR::conflict conflict,
      #   IR::counterexample example) -> void
      def append_witness_steps(lines, state, conflict, example)
        lines << "  1. Reach state #{state.id} with the witness prefix."
        sentence = example.fetch(:sentence).map { |name| display_name(name) }
        sentence.insert(example.fetch(:lookahead_index), "•")
        kind = example.fetch(:unifying) ? "Unifying counterexample" : "Nonunifying reachability witness"
        lines << "     #{kind}: #{sentence.join(' ')}"
        lines << "  2. The lookahead permits these competing actions:"
        conflict_alternatives(conflict).each { |alternative| lines << "     - #{alternative_text(alternative)}" }
        resolution = conflict.fetch(:resolution)
        lines << "  3. Resolution: #{resolution.fetch(:by)} chose #{resolution.fetch(:chose)}."
      end

      # @rbs (Array[String] lines, IR::counterexample example) -> void
      def append_interpretations(lines, example)
        lines << "  Competing derivations:"
        example.fetch(:interpretations).each_with_index do |interpretation, index|
          lines << "    #{index + 1}. #{interpretation.fetch(:kind)}"
          append_tree(lines, interpretation.fetch(:tree), "       ", "")
        end
      end

      # @rbs (Hash[Symbol, untyped] alternative) -> String
      def alternative_text(alternative)
        return "shift to state #{alternative.fetch(:state)}" if alternative.fetch(:kind) == "shift"

        "reduce by production #{alternative.fetch(:production)}"
      end

      # @rbs (Array[String] lines, untyped tree, String prefix, String connector) -> void
      def append_tree(lines, tree, prefix, connector)
        unless tree.is_a?(Hash)
          lines << "#{prefix}#{connector}#{display_name(tree.to_s)}"
          return
        end

        name = tree[:symbol] || tree[:token]
        production = tree[:production] ? " (production #{tree[:production]})" : ""
        lines << "#{prefix}#{connector}#{display_name(name.to_s)}#{production}"
        children = tree.fetch(:children, [])
        continuation = { "" => "", "|- " => "|  " }.fetch(connector, "   ")
        child_prefix = "#{prefix}#{continuation}"
        children.each_with_index do |child, index|
          branch = index == children.length - 1 ? "`- " : "|- "
          append_tree(lines, child, child_prefix, branch)
        end
      end

      # @rbs (IR::GrammarSymbol symbol, ?query: String?) -> String
      def token_label(symbol, query: nil)
        label = if symbol.display_name && symbol.display_name != symbol.name
                  "#{symbol.name} (display #{symbol.display_name.inspect})"
                else
                  symbol.name
                end
        query && query != symbol.name ? "#{label}, selected by #{query.inspect}" : label
      end

      # @rbs (String name) -> String
      def display_name(name) = @grammar.symbol(name)&.then { |symbol| @labels.fetch(symbol.id, symbol.name) } || name
    end
    # rubocop:enable Metrics/ClassLength
  end
end
