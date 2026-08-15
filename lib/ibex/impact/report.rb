# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Impact
    # Builds the deterministic public impact-v1 document.
    class Report
      # @rbs (mode: String, algorithm: String, grammar: IR::Grammar, before: IR::Automaton?, after: IR::Automaton?,
      #   seeds: Array[Hash[Symbol, Object?]], nodes: Hash[Integer, Node], symbol_kinds: Hash[Integer, Array[String]],
      #   set_changes: Hash[String, Hash[Symbol, Object?]], automaton: Hash[Symbol, Object?],
      #   actions: Array[Hash[Symbol, Object?]], coverage: Hash[Symbol, Object?], ?minimum: String,
      #   ?warnings: Array[String]) -> void
      # rubocop:disable Metrics/ParameterLists
      def initialize(mode:, algorithm:, grammar:, before:, after:, seeds:, nodes:, symbol_kinds:, set_changes:,
                     automaton:,
                     actions:, coverage:, minimum: "info", warnings: [])
        @mode = mode
        @algorithm = algorithm
        @grammar = grammar
        @before = before
        @after = after
        @seeds = seeds
        @nodes = nodes
        @symbol_kinds = symbol_kinds
        @set_changes = set_changes
        @automaton = automaton
        @actions = actions
        @coverage = coverage
        @minimum = minimum
        @warnings = warnings
      end
      # rubocop:enable Metrics/ParameterLists

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        symbols = symbol_documents
        action_documents = @actions.sort_by { |action| action.fetch(:production) }
        {
          ibex_report: "impact", schema_version: 1, mode: @mode, algorithm: @algorithm,
          grammar_digest: { before: @before&.grammar_digest, after: @after&.grammar_digest },
          seeds: @seeds.map { |seed| seed.slice(:symbol, :origin, :nullable_boundary) },
          symbols: symbols, automaton: @automaton, actions: action_documents, coverage: @coverage,
          warnings: @warnings.sort, totals: totals(symbols, action_documents)
        }
      end

      private

      # @rbs () -> Array[Hash[Symbol, Object?]]
      def symbol_documents
        ids = (@nodes.keys + @set_changes.keys.filter_map { |name| @grammar.symbol(name)&.id }).uniq.sort
        documents = ids.filter_map { |id| symbol_document(id) }
        documents.select { |document| Severity::RANK.fetch(document.fetch(:severity)) >= Severity::RANK.fetch(@minimum) }
      end

      # @rbs (Integer) -> Hash[Symbol, Object?]?
      def symbol_document(id)
        return unless nonterminal?(id)

        symbol = @grammar.symbol_by_id(id)
        node = @nodes[id]
        name = symbol.name
        kinds = (@symbol_kinds[id] || []).uniq.sort
        kinds = ["reference"] if kinds.empty? && node
        severity = document_severity(name, kinds)
        {
          symbol: name, severity: severity, kinds: kinds, distance: node&.distance || 0,
          component: component_names(node, id),
          sets: @set_changes.fetch(name, { first: empty_change, follow: empty_change, nullable: nil }),
          witness: witness_documents(node&.witness || [])
        }
      end

      # @rbs (Integer) -> bool
      def nonterminal?(id)
        @grammar.symbol_by_id(id)&.nonterminal? || false
      end

      # @rbs (String, Array[String]) -> String
      def document_severity(name, kinds)
        level = kinds.reduce("info") { |current, kind| Severity.max(current, kind_severity(kind)) }
        action_severity(name, level)
      end

      # @rbs (Node?, Integer) -> Array[String]
      def component_names(node, id)
        (node&.component || [id]).sort.map { |member| @grammar.symbol_by_id(member)&.name }.compact.sort
      end

      # @rbs (String kind) -> String
      def kind_severity(kind)
        return "high" if %w[first follow nullable action_arity].include?(kind)
        return "medium" if kind == "reference"

        "info"
      end

      # @rbs (String name, String current) -> String
      def action_severity(name, current)
        findings = @actions.select { |action| action.fetch(:production).start_with?("#{name} ->") }
        findings.reduce(current) { |level, finding| Severity.max(level, finding.fetch(:severity)) }
      end

      # @rbs () -> Hash[Symbol, Array[String]]
      def empty_change
        { added: [], removed: [] }
      end

      # @rbs (Array[Edge]) -> Array[Hash[Symbol, Object?]]
      def witness_documents(witness)
        witness.map do |edge|
          production = edge.production && @grammar.productions[edge.production]
          {
            from: symbol_name(edge.source), to: symbol_name(edge.target), production: production_shape(production),
            loc: production&.origin&.fetch(:loc, nil)
          }
        end
      end

      # @rbs (Integer) -> String
      def symbol_name(id)
        @grammar.symbol_by_id(id)&.name || id.to_s
      end

      # @rbs (IR::Production?) -> String?
      def production_shape(production)
        return unless production

        lhs = symbol_name(production.lhs)
        rhs = production.rhs.map { |id| symbol_name(id) }
        "#{lhs} -> #{rhs.join(' ')}"
      end

      # @rbs (Array[Hash[Symbol, Object?]], Array[Hash[Symbol, Object?]]) -> Hash[Symbol, Integer]
      def totals(symbols, actions)
        counts = Severity::LEVELS.to_h { |level| [level.to_sym, 0] }
        symbols.each { |item| counts[item.fetch(:severity).to_s.to_sym] += 1 }
        actions.each { |item| counts[item.fetch(:severity).to_s.to_sym] += 1 }
        counts
      end
    end
  end
end
