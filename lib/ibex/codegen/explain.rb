# frozen_string_literal: true

require_relative "../lalr"
require_relative "symbol_labels"

module Ibex
  module Codegen
    # @rbs!
    #   type explain_selection = {
    #     state: IR::AutomatonState,
    #     conflict: IR::conflict,
    #     conflict_index: Integer
    #   }
    #
    #   type explain_entry = {
    #     state: IR::AutomatonState,
    #     conflict: IR::conflict,
    #     example: LALR::search_counterexample
    #   }
    #
    #   type explain_token = { name: String, display_name: String?, label: String, ?query: String }
    #   type explain_alternative = { kind: String, ?state: Integer, ?production: Integer }
    #   type explain_search = {
    #     status: String, explored: Integer, exhausted: bool, bounds: Hash[Symbol, Integer]
    #   }
    #   type explain_tree_node = {
    #     ?symbol: explain_token, ?token: explain_token, ?production: Integer, ?children: Array[explain_tree]
    #   }
    #   type explain_tree = untyped
    #   type explain_interpretation = Hash[Symbol, untyped]
    #   type string_value = String | Integer | Symbol

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

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        entries = @entries #: Array[explain_entry]
        automaton = @automaton #: IR::Automaton
        unifying = entries.count { |entry| entry.fetch(:example).fetch(:unifying) }
        inconclusive = entries.count { |entry| entry.fetch(:example).fetch(:inconclusive) }
        {
          ibex_explain: "conflicts",
          schema_version: SCHEMA_VERSION,
          algorithm: automaton.algorithm,
          selectors: {
            state: @state_selector,
            token: @token_selector && token_reference(@token_selector, query: @token_query)
          },
          search: { max_tokens: @max_tokens, max_configurations: @max_configurations },
          summary: {
            matched_conflicts: entries.length,
            unifying_counterexamples: unifying,
            nonunifying_witnesses: entries.length - unifying - inconclusive,
            inconclusive_searches: inconclusive
          },
          conflicts: entries.map { |entry| conflict_document(entry) }
        }
      end

      # @rbs () -> String
      def render_text
        automaton = @automaton #: IR::Automaton
        entries = @entries #: Array[explain_entry]
        state_selector = @state_selector #: Integer?
        token_selector = @token_selector #: IR::GrammarSymbol?
        lines = [
          "Ibex conflict explanation v#{SCHEMA_VERSION}",
          "Algorithm: #{automaton.algorithm}",
          "State selector: #{state_selector || 'all'}",
          "Token selector: #{token_selector ? token_label(token_selector, query: @token_query) : 'all'}",
          "Search budget: #{@max_tokens} tokens, #{@max_configurations} configurations",
          "Matched conflicts: #{entries.length}",
          ""
        ]
        if entries.empty?
          lines << "No conflicts matched the selectors."
        else
          entries.each_with_index { |entry, index| append_conflict(lines, entry, index + 1) }
        end
        "#{lines.join("\n")}\n"
      end

      private

      # @rbs (String? query) -> IR::GrammarSymbol?
      def resolve_token(query)
        return unless query

        grammar = @grammar #: IR::Grammar
        canonical = grammar.terminals.find { |symbol| symbol.name == query }
        return canonical if canonical

        displayed = grammar.terminals.select { |symbol| symbol.display_name == query }
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
        state_selector = @state_selector #: Integer?
        automaton = @automaton #: IR::Automaton
        return unless state_selector
        return if state_selector >= 0 && automaton.states.any? { |state| state.id == state_selector }

        raise Ibex::Error, "(cli):1:1: unknown automaton state #{state_selector}"
      end

      # @rbs () -> Array[explain_entry]
      def select_entries
        selections = selected_conflicts
        return [] if selections.empty?

        automaton = @automaton #: IR::Automaton
        counterexamples = LALR::Counterexample.new(
          automaton, max_tokens: @max_tokens, max_configurations: @max_configurations
        )
        selections.map do |selection|
          state = selection.fetch(:state)
          {
            state: state,
            conflict: selection.fetch(:conflict),
            example: counterexamples.for_conflict(state.id, selection.fetch(:conflict_index))
          }
        end
      end

      # @rbs () -> Array[explain_selection]
      def selected_conflicts
        automaton = @automaton #: IR::Automaton
        state_selector = @state_selector #: Integer?
        token_selector = @token_selector #: IR::GrammarSymbol?
        automaton.states.flat_map do |state|
          state.conflicts.each_with_index.filter_map do |conflict, conflict_index|
            next if state_selector && state.id != state_selector
            next if token_selector && conflict[:symbol] != token_selector.name

            { state: state, conflict: conflict, conflict_index: conflict_index }
          end
        end
      end

      # @rbs (explain_entry entry) -> Hash[Symbol, Object?]
      def conflict_document(entry)
        state = entry.fetch(:state)
        conflict = entry.fetch(:conflict)
        example = entry.fetch(:example)
        document = {
          state: state.id,
          type: conflict.fetch(:type).to_s,
          token: symbol_reference(conflict.fetch(:symbol)),
          alternatives: conflict_alternatives(conflict),
          resolution: string_values(conflict.fetch(:resolution)),
          witness: {
            kind: witness_kind(example),
            sentence: example.fetch(:sentence).map { |name| symbol_reference(name) },
            lookahead_index: example.fetch(:lookahead_index),
            symbol_path: example.fetch(:symbol_path).map { |name| symbol_reference(name) },
            search: search_document(example.fetch(:search)),
            interpretations: example.fetch(:interpretations).map { |item| interpretation_document(item) }
          }
        } #: Hash[Symbol, Object?]
        document[:midrule_origins] = conflict[:midrule_origins] if conflict[:midrule_origins]
        document
      end

      # @rbs (LALR::search_counterexample example) -> String
      def witness_kind(example)
        return "unifying_counterexample" if example.fetch(:unifying)
        return "inconclusive" if example.fetch(:inconclusive)

        "nonunifying_witness"
      end

      # @rbs (LALR::search_outcome outcome) -> explain_search
      def search_document(outcome)
        {
          status: outcome.fetch(:status).to_s,
          explored: outcome.fetch(:explored),
          exhausted: outcome.fetch(:exhausted),
          bounds: outcome.fetch(:bounds)
        }
      end

      # @rbs (IR::conflict conflict) -> Array[explain_alternative]
      def conflict_alternatives(conflict)
        case conflict[:type]
        when :shift_reduce
          shift = { kind: "shift", state: conflict.fetch(:shift_to) } # @type var shift: explain_alternative
          reduce = { kind: "reduce", production: conflict.fetch(:reduce) } # @type var reduce: explain_alternative
          [shift, reduce]
        when :reduce_reduce
          reduce_reduce = conflict #: IR::reduce_reduce_conflict
          reduce_reduce[:reductions].map do |production|
            { kind: "reduce", production: production }
          end #: Array[explain_alternative]
        else
          []
        end
      end

      # @rbs (IR::interpretation interpretation) -> explain_interpretation
      def interpretation_document(interpretation)
        kind = interpretation.fetch(:kind) #: Symbol
        tree = interpretation.fetch(:tree) #: explain_tree
        value = { kind: kind.to_s,
                  tree: tree_document(tree) } # @type var value: explain_interpretation
        value[:state] = interpretation[:state] if interpretation.key?(:state)
        value[:production] = interpretation[:production] if interpretation.key?(:production)
        value
      end

      # @rbs (explain_tree tree) -> explain_tree
      def tree_document(tree)
        return symbol_reference(tree.to_s) unless tree.is_a?(Hash)

        node = tree #: explain_tree_node
        value = {} # @type var value: explain_tree_node
        value[:symbol] = symbol_reference(node[:symbol].to_s) if node[:symbol]
        value[:token] = symbol_reference(node[:token].to_s) if node[:token]
        value[:production] = node[:production] if node[:production]
        value[:children] = node[:children].map { |child| tree_document(child) } if node[:children]
        value
      end

      # @rbs (Hash[Symbol, string_value] value) -> Hash[Symbol, string_value]
      def string_values(value)
        values = value #: Hash[Symbol, string_value]
        values.transform_values { |item| item.is_a?(Symbol) ? item.to_s : item }
      end

      # @rbs (String name) -> explain_token
      def symbol_reference(name)
        grammar = @grammar #: IR::Grammar
        symbol = grammar.symbol(name)
        return { name: name, display_name: nil, label: name } unless symbol

        token_reference(symbol)
      end

      # @rbs (IR::GrammarSymbol symbol, ?query: String?) -> explain_token
      def token_reference(symbol, query: nil)
        labels = @labels #: Hash[Integer, String]
        value = { name: symbol.name, display_name: symbol.display_name,
                  label: labels.fetch(symbol.id, symbol.name) } # @type var value: explain_token
        value[:query] = query if query
        value
      end

      # @rbs (Array[String] lines, explain_entry entry, Integer number) -> void
      def append_conflict(lines, entry, number)
        state = entry.fetch(:state)
        conflict = entry.fetch(:conflict)
        example = entry.fetch(:example)
        grammar = @grammar #: IR::Grammar
        token = grammar.symbol(conflict.fetch(:symbol))
        token_text = token ? token_label(token) : conflict.fetch(:symbol)
        type = conflict.fetch(:type).to_s.tr("_", "/")
        lines << "Conflict #{number}: state #{state.id}, #{type}, token #{token_text}"
        append_midrule_origins(lines, conflict)
        append_witness_steps(lines, state, conflict, example)
        append_interpretations(lines, example)
        if example.fetch(:inconclusive)
          search = example.fetch(:search)
          lines << "  Search exhausted after #{search.fetch(:explored)} configurations; classification is inconclusive."
        elsif !example.fetch(:unifying)
          lines << "  The search found no shared sentence within the configured budget; this witness is deterministic."
        end
        lines << ""
      end

      # @rbs (Array[String] lines, IR::conflict conflict) -> void
      def append_midrule_origins(lines, conflict)
        origins = conflict[:midrule_origins]
        return unless origins

        origins.each do |origin|
          lines << "  Midrule action origin: #{origin.fetch(:file)}:#{origin.fetch(:line)}:#{origin.fetch(:column)}"
        end
      end

      # @rbs (Array[String] lines, IR::AutomatonState state, IR::conflict conflict,
      #   LALR::search_counterexample example) -> void
      def append_witness_steps(lines, state, conflict, example)
        lines << "  1. Reach state #{state.id} with the witness prefix."
        sentence = example.fetch(:sentence).map { |name| display_name(name) }
        sentence.insert(example.fetch(:lookahead_index), "•")
        kind = case witness_kind(example)
               when "unifying_counterexample" then "Unifying counterexample"
               when "inconclusive" then "Inconclusive reachability witness"
               else "Nonunifying reachability witness"
               end
        lines << "     #{kind}: #{sentence.join(' ')}"
        lines << "  2. The lookahead permits these competing actions:"
        conflict_alternatives(conflict).each { |alternative| lines << "     - #{alternative_text(alternative)}" }
        resolution = conflict.fetch(:resolution)
        lines << "  3. Resolution: #{resolution.fetch(:by)} chose #{resolution.fetch(:chose)}."
      end

      # @rbs (Array[String] lines, LALR::search_counterexample example) -> void
      def append_interpretations(lines, example)
        lines << "  Competing derivations:"
        example.fetch(:interpretations).each_with_index do |interpretation, index|
          lines << "    #{index + 1}. #{interpretation.fetch(:kind)}"
          append_tree(lines, interpretation.fetch(:tree), "       ", "")
        end
      end

      # @rbs (explain_alternative alternative) -> String
      def alternative_text(alternative)
        return "shift to state #{alternative.fetch(:state)}" if alternative.fetch(:kind) == "shift"

        "reduce by production #{alternative.fetch(:production)}"
      end

      # @rbs (Array[String] lines, explain_tree tree, String prefix, String connector) -> void
      def append_tree(lines, tree, prefix, connector)
        unless tree.is_a?(Hash)
          lines << "#{prefix}#{connector}#{display_name(tree.to_s)}"
          return
        end

        node = tree #: explain_tree_node
        name = node[:symbol] || node[:token]
        production = node[:production] ? " (production #{node[:production]})" : ""
        lines << "#{prefix}#{connector}#{display_name(name.to_s)}#{production}"
        children = node.fetch(:children, [])
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
      def display_name(name)
        grammar = @grammar #: IR::Grammar
        labels = @labels #: Hash[Integer, String]
        grammar.symbol(name)&.then { |symbol| labels.fetch(symbol.id, symbol.name) } || name
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
