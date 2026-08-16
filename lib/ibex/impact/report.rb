# frozen_string_literal: true
# rbs_inline: enabled

require "digest"
require_relative "../ir/serialize"

module Ibex
  module Impact
    # Builds the deterministic public impact-v1 document.
    class Report
      # @rbs @mode: String
      # @rbs @algorithm: String
      # @rbs @grammar: IR::Grammar
      # @rbs @before: IR::Automaton?
      # @rbs @after: IR::Automaton?
      # @rbs @seeds: Array[Hash[Symbol, Object?]]
      # @rbs @nodes: Hash[Integer, Node]
      # @rbs @symbol_kinds: Hash[Integer, Array[String]]
      # @rbs @set_changes: Hash[String, Hash[Symbol, Object?]]
      # @rbs @automaton: Hash[Symbol, Object?]
      # @rbs @actions: Array[Hash[Symbol, Object?]]
      # @rbs @coverage: Hash[Symbol, Object?]
      # @rbs @minimum: String
      # @rbs @warnings: Array[String]
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
        @automaton = automaton #: Hash[Symbol, Object?]
        @actions = actions #: Array[Hash[Symbol, Object?]]
        @coverage = coverage #: Hash[Symbol, Object?]
        @minimum = minimum
        @warnings = warnings
      end
      # rubocop:enable Metrics/ParameterLists

      # @rbs (?minimum: String) -> Hash[Symbol, Object?]
      def to_h(minimum: @minimum)
        symbols = symbol_documents(minimum)
        action_records = action_documents
        {
          ibex_report: "impact", schema_version: 1, mode: @mode, algorithm: @algorithm,
          grammar_digest: { before: stable_grammar_digest(@before), after: stable_grammar_digest(@after) },
          seeds: @seeds.map { |seed| seed.slice(:symbol, :origin, :nullable_boundary) },
          symbols: symbols, automaton: @automaton, actions: action_records,
          coverage: coverage_document, warnings: stable_warnings,
          totals: totals(symbols, action_records, @automaton)
        }
      end

      private

      # @rbs (String minimum) -> Array[Hash[Symbol, Object?]]
      def symbol_documents(minimum)
        ids = (@nodes.keys + @set_changes.keys.filter_map { |name| @grammar.symbol(name)&.id }).uniq.sort
        documents = ids.filter_map { |id| symbol_document(id) }
        documents.select { |document| Severity::RANK.fetch(severity_of(document)) >= Severity::RANK.fetch(minimum) }
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
        findings = @actions.select { |action| action_production(action).start_with?("#{name} ->") }
        findings.reduce(current) { |level, finding| Severity.max(level, severity_of(finding)) }
      end

      # @rbs (Hash[Symbol, Object?] record) -> String
      def severity_of(record)
        record.fetch(:severity) #: String
      end

      # @rbs () -> Hash[Symbol, Array[String]]
      def empty_change
        { added: [], removed: [] }
      end

      # @rbs (Array[Edge]) -> Array[Hash[Symbol, Object?]]
      def witness_documents(witness)
        witness.map do |edge|
          production = edge.production && @grammar.productions[edge.production]
          location = production&.origin&.fetch(:loc, nil) #: IR::location?
          {
            from: symbol_name(edge.source), to: symbol_name(edge.target), production: production_shape(production),
            loc: stable_location(location)
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

      # @rbs (Array[Hash[Symbol, Object?]], Array[Hash[Symbol, Object?]],
      #   Hash[Symbol, Object?]) -> Hash[Symbol, Integer]
      def totals(symbols, actions, automaton)
        counts = Severity::LEVELS.to_h { |level| [level.to_sym, 0] }
        symbols.each { |item| counts[item.fetch(:severity).to_s.to_sym] += 1 }
        actions.each { |item| counts[item.fetch(:severity).to_s.to_sym] += 1 }
        conflicts = automaton.dig(:conflicts, :added) || [] #: Array[Hash[Symbol, Object?]]
        counts[:critical] += conflicts.length
        unreachable = automaton.fetch(:unreachable, []) #: Array[Integer]
        counts[:critical] += unreachable.length
        counts
      end

      # @rbs () -> Array[Hash[Symbol, Object?]]
      def action_documents
        @actions.sort_by { |action| action_production(action) }.map do |action|
          production = action_production(action)
          severity = action.fetch(:severity) #: String
          reason = action.fetch(:reason) #: String
          context_length = action.fetch(:context_length) #: Hash[Symbol, Integer]
          location = action.fetch(:loc, nil) #: IR::location?
          {
            production: production, severity: severity, reason: reason,
            context_length: context_length, loc: stable_location(location)
          }
        end
      end

      # @rbs (Hash[Symbol, Object?] action) -> String
      def action_production(action)
        action.fetch(:production) #: String
      end

      # @rbs () -> Hash[Symbol, Object?]
      def coverage_document
        empty_reports = [] #: Array[Hash[Symbol, Object?]]
        reports = @coverage.fetch(:reports, empty_reports) #: Array[Hash[Symbol, Object?]]
        status = @coverage.fetch(:status) #: String
        { status: status,
          reports: reports.sort_by { |report| coverage_report_path(report) }.map do |report|
            productions = report.fetch(:productions) #: Array[Integer]
            { path: stable_path(coverage_report_path(report)), productions: productions.sort }
          end }
      end

      # @rbs (Hash[Symbol, Object?] report) -> String
      def coverage_report_path(report)
        report.fetch(:path) #: String
      end

      # @rbs () -> Array[String]
      def stable_warnings
        empty_reports = [] #: Array[Hash[Symbol, Object?]]
        paths = @coverage.fetch(:reports, empty_reports).map { |report| coverage_report_path(report) }
        @warnings.map do |warning|
          paths.reduce(warning) { |current, path| current.gsub(path, stable_path(path)) }
        end.sort
      end

      # @rbs (IR::location?) -> Hash[Symbol, Integer]?
      def stable_location(location)
        return unless location

        { line: location[:line], column: location[:column] }
      end

      # @rbs (IR::Automaton?) -> String?
      def stable_grammar_digest(automaton)
        return unless automaton

        serialized = IR::Serialize.dump(automaton.grammar)
        canonical = serialized.gsub(/"file":\s*"[^"]*"/, '"file": "<source>"')
        canonical = canonical.gsub(/"root":\s*"[^"]*"/, '"root": null')
        "sha256:#{Digest::SHA256.hexdigest(canonical)}"
      end

      # @rbs (String) -> String
      def stable_path(path)
        return path unless path.start_with?(File::SEPARATOR)

        File.basename(path)
      end
    end
  end
end
