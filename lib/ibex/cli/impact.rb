# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../diff"
require_relative "../impact"

module Ibex
  # CLI adapter for potential and confirmed grammar impact reports.
  # rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize
  module CLIImpact
    include CLIAnalysis

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_impact_command(arguments)
      settings = impact_option_parser(arguments)
      if settings[:help]
        @stdout.puts(settings.fetch(:help))
        return 0
      end
      paths = settings.fetch(:paths)
      unless [1, 2].include?(paths.length)
        raise Ibex::Error, "(impact):1:1: impact requires one grammar or two grammar files"
      end

      extend CLIAnalysis unless singleton_class.ancestors.include?(CLIAnalysis)
      settings[:algorithm] = local_configuration_value(settings, "parser.algorithm")
      analysis = if paths.length == 1
                   potential_impact(paths, settings)
                 else
                   confirmed_impact(paths, settings)
                 end
      report, identities, gate_report = analysis
      apply_baseline(report, identities, settings)
      apply_baseline(gate_report, identities, settings)
      write_impact_report(report, settings.fetch(:format))
      Impact::Severity.fails?(gate_report, settings.fetch(:fail_on)) ? 1 : 0
    end

    # @rbs (Array[String]) -> Hash[Symbol, untyped]
    def impact_option_parser(arguments)
      settings = {
        paths: [], symbols: [], depth: nil, kinds: [:all], severity: "medium", coverage: [],
        fail_on: [], format: "json", update_baseline: false, configuration_explicit: [],
        algorithm: Configuration::Registry.fetch("parser.algorithm").default,
        mode: Configuration::Registry.fetch("grammar.mode").default
      } #: Hash[Symbol, untyped]
      # rubocop:disable Metrics/BlockLength
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex impact [options] GRAMMAR or OLD NEW"
        options.on("--symbol=NAME[,NAME]", "seed nonterminals for a one-version analysis") do |value|
          settings[:symbols].concat(value.split(",").map(&:strip))
        end
        options.on("--depth=N", Integer, "maximum propagation depth") do |value|
          raise OptionParser::InvalidArgument, "--depth must be non-negative" if value.negative?

          settings[:depth] = value
        end
        options.on("--kind=LIST", "reference, first, or follow") { |value| settings[:kinds] = parse_kinds(value) }
        options.on("--severity=LEVEL", Impact::Severity::LEVELS, "minimum severity") do |value|
          settings[:severity] = value
        end
        options.on("--coverage=PATH", "runtime coverage report (repeatable)") { |value| settings[:coverage] << value }
        options.on("--baseline=PATH", "known conflict baseline") { |value| settings[:baseline] = value }
        options.on("--update-baseline", "write the current conflict baseline") { settings[:update_baseline] = true }
        options.on("--fail-on=LIST", "CI gate conditions") do |value|
          settings[:fail_on] = Impact::Severity.validate_gates(value.split(",").map(&:strip))
        end
        options.on(
          "--algorithm=NAME", Configuration::Registry::CLI_ALGORITHM_VALUES, "algorithm for grammar inputs"
        ) do |value|
          set_local_configuration_option(settings, :algorithm, value.to_sym)
        end
        options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
          set_local_configuration_option(settings, :mode, value.to_sym)
          set_configuration_option(:mode, value.to_sym)
        end
        options.on("--format=FORMAT", %w[json text], "json or text") { |value| settings[:format] = value }
        options.on("--help", "show help") { settings[:help] = options.to_s }
      end
      # rubocop:enable Metrics/BlockLength
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (String value) -> Array[Symbol]
    def parse_kinds(value)
      kinds = value.split(",").map(&:strip).map(&:to_sym)
      unknown = kinds - %i[reference first follow]
      raise OptionParser::InvalidArgument, "unknown impact kind #{unknown.first.inspect}" unless unknown.empty?

      kinds.uniq
    end

    # @rbs (Array[String], Hash[Symbol, untyped]) -> [Hash[Symbol, Object?], Array[String], Hash[Symbol, Object?]]
    def potential_impact(paths, settings)
      automaton = load_analysis_automaton(paths.fetch(0), settings.fetch(:algorithm), explicit: algo_set?(settings))
      names = settings.fetch(:symbols)
      raise Ibex::Error, "(impact):1:1: one-version impact requires --symbol" if names.empty?

      seeds = Impact::Seeds.new(automaton.grammar, names)
      graph = Impact::Graph.new(automaton.grammar)
      nodes, symbol_kinds = propagate(graph, seeds.ids, settings)
      automaton_impact = Impact::AutomatonImpact.new(automaton, nodes.keys)
      coverage = load_coverage(automaton, automaton_impact.production_ids, settings)
      reporter = Impact::Report.new(
        mode: "potential", algorithm: automaton.algorithm, grammar: automaton.grammar, before: nil, after: automaton,
        seeds: seeds.records, nodes: nodes, symbol_kinds: symbol_kinds, set_changes: {},
        automaton: potential_automaton_document(automaton, automaton_impact), actions: [], coverage: coverage.to_h,
        minimum: settings.fetch(:severity), warnings: nullable_warnings(seeds, coverage)
      )
      [reporter.to_h, conflict_identities(automaton), reporter.to_h(minimum: "info")]
    end

    # @rbs (Array[String], Hash[Symbol, untyped]) -> [Hash[Symbol, Object?], Array[String], Hash[Symbol, Object?]]
    def confirmed_impact(paths, settings)
      before = load_analysis_automaton(paths.fetch(0), settings.fetch(:algorithm), explicit: algo_set?(settings))
      after = load_analysis_automaton(paths.fetch(1), settings.fetch(:algorithm), explicit: algo_set?(settings))
      diff = Diff.new(before, after).to_h
      rules = diff.fetch(:rules) #: Hash[Symbol, Array[Hash[Symbol, Object?]]]
      names = rules.values_at(:added, :removed, :changed).flatten.map do |record|
        record.fetch(:id).to_s
      end.uniq.sort
      seed_names = names.select { |name| after.grammar.symbol(name) }
      seeds = Impact::Seeds.new(after.grammar, seed_names, origin: "diff")
      removed_seed_names = names.reject { |name| after.grammar.symbol(name) }
      removed_seeds = Impact::Seeds.new(before.grammar, removed_seed_names, origin: "diff")
      seed_records = (seeds.records + removed_seeds.records).sort_by { |record| record.fetch(:symbol).to_s }
      symbol_changes = diff.fetch(:symbols) #: Hash[Symbol, Array[Hash[Symbol, Object?]]]
      metadata_names = symbol_changes.values.flatten.map { |record| record.fetch(:id).to_s }.uniq.sort
      graph = Impact::Graph.new(after.grammar)
      nodes, symbol_kinds = propagate(graph, seeds.ids, settings)
      set_changes, changed_kinds = compare_sets(before, after)
      symbol_kinds = merge_symbol_kinds(symbol_kinds, changed_kinds, after.grammar)
      precedence_kinds = precedence_symbol_kinds(symbol_changes, after.grammar)
      symbol_kinds = merge_symbol_kinds(symbol_kinds, precedence_kinds, after.grammar)
      automaton_impact = Impact::AutomatonImpact.new(after, nodes.keys)
      actions = Impact::ActionImpact.new(before.grammar, after.grammar, affected_names: names).to_a
      coverage = load_coverage(after, automaton_impact.production_ids, settings)
      reporter = Impact::Report.new(
        mode: "diff", algorithm: after.algorithm, grammar: after.grammar, before: before, after: after,
        seeds: seed_records, nodes: nodes, symbol_kinds: symbol_kinds, set_changes: set_changes,
        metadata_names: metadata_names,
        automaton: confirmed_automaton_document(before, after, diff, automaton_impact), actions: actions,
        coverage: coverage.to_h, minimum: settings.fetch(:severity), warnings: coverage.warnings
      )
      [reporter.to_h, conflict_identities(after), reporter.to_h(minimum: "info")]
    end

    # @rbs (Impact::Graph, Array[Integer], Hash[Symbol, untyped]) ->
    #   [Hash[Integer, Impact::Node], Hash[Integer, Array[String]]]
    def propagate(graph, seed_ids, settings)
      kinds = settings.fetch(:kinds) == [:all] ? %i[reference first follow] : settings.fetch(:kinds)
      nodes = {} #: Hash[Integer, Impact::Node]
      symbol_kinds = Hash.new { |hash, key| hash[key] = [] } #: Hash[Integer, Array[String]]
      kinds.each do |kind|
        current = Impact::Propagation.new(graph).propagate(seed_ids, kind, max_depth: settings[:depth])
        current.each do |id, node|
          best = nodes[id]
          nodes[id] = node if best.nil? || node.distance < best.distance
          symbol_kinds[id] << kind.to_s unless node.distance.zero? && node.witness.empty?
        end
      end
      [nodes.sort.to_h, symbol_kinds.transform_values { |value| value.uniq.sort }]
    end

    # @rbs (IR::Automaton, Array[Integer], Hash[Symbol, untyped]) -> Impact::CoverageImpact
    def load_coverage(automaton, production_ids, settings)
      reports = settings.fetch(:coverage).map { |path| [path, Coverage::Report.load_file(path)] }
      Impact::CoverageImpact.new(automaton, production_ids, reports)
    end

    # @rbs (Impact::Seeds, Impact::CoverageImpact) -> Array[String]
    def nullable_warnings(seeds, coverage)
      warnings = coverage.warnings.dup
      seeds.records.each do |seed|
        next unless seed.fetch(:nullable_boundary)

        warnings << "#{seed.fetch(:symbol)}: nullable boundary may make potential propagation " \
                    "incomplete; compare two versions"
      end
      warnings
    end

    # @rbs (IR::Automaton, Impact::AutomatonImpact) -> Hash[Symbol, Object?]
    def potential_automaton_document(automaton, impact)
      added = conflict_identities(automaton).map { |id| { id: id, value: nil } } #: Array[Hash[Symbol, Object?]]
      removed = [] #: Array[Hash[Symbol, Object?]]
      changed = [] #: Array[Hash[Symbol, Object?]]
      { states: { before: nil, after: automaton.states.length, delta: nil },
        affected_states: impact.affected_states,
        conflicts: { added: added, removed: removed, changed: changed },
        unreachable: unreachable_state_ids(automaton),
        unreachable_nonterminals: unreachable_nonterminal_names(automaton.grammar) }
    end

    # @rbs (IR::Automaton, IR::Automaton, Hash[Symbol, Object?], Impact::AutomatonImpact) -> Hash[Symbol, Object?]
    def confirmed_automaton_document(before, after, diff, impact)
      {
        states: {
          before: before.states.length, after: after.states.length, delta: after.states.length - before.states.length
        },
        affected_states: impact.affected_states, conflicts: diff.fetch(:conflicts),
        unreachable: newly_unreachable_state_ids(before, after),
        unreachable_nonterminals: newly_unreachable_nonterminal_names(before.grammar, after.grammar)
      }
    end

    # @rbs (IR::Grammar) -> Array[String]
    def unreachable_nonterminal_names(grammar)
      grammar.warnings.filter_map do |warning|
        next unless warning.fetch(:type).to_sym == :unreachable_nonterminal

        warning.fetch(:symbol).to_s
      end.uniq.sort
    end

    # @rbs (IR::Grammar, IR::Grammar) -> Array[String]
    def newly_unreachable_nonterminal_names(before, after)
      unreachable_nonterminal_names(after) - unreachable_nonterminal_names(before)
    end

    # @rbs (IR::Automaton) -> Array[Integer]
    def unreachable_state_ids(automaton)
      reachable = LALR::UnreachableStates.reachable_states(automaton.states, automaton.entry_states.values)
      (0...automaton.states.length).to_a - reachable
    end

    # @rbs (IR::Automaton, IR::Automaton) -> Array[Integer]
    def newly_unreachable_state_ids(before, after)
      before_keys = unreachable_state_keys(before)
      unreachable_state_ids(after).reject { |id| before_keys.include?(unreachable_state_key(after, id)) }
    end

    # @rbs (IR::Automaton) -> Array[String]
    def unreachable_state_keys(automaton)
      unreachable_state_ids(automaton).map { |id| unreachable_state_key(automaton, id) }
    end

    # @rbs (IR::Automaton, Integer) -> String
    def unreachable_state_key(automaton, id)
      state = automaton.states.fetch(id)
      items = state.items.map do |item|
        production_name = if item.production == LALR::Builder::AUGMENTED_PRODUCTION
                            "$accept"
                          else
                            production = automaton.grammar.productions.fetch(item.production)
                            production_shape(automaton.grammar, production.id)
                          end
        [production_name, item.dot,
         item.lookaheads.map { |lookahead| automaton.grammar.symbol_by_id(lookahead)&.name || lookahead.to_s }]
      end.sort_by(&:inspect)
      JSON.generate(items)
    end

    # @rbs (IR::Automaton, IR::Automaton) ->
    #   [Hash[String, Hash[Symbol, Object?]], Hash[String, Array[String]]]
    def compare_sets(before, after)
      before_sets = Analysis::Sets.new(before.grammar)
      after_sets = Analysis::Sets.new(after.grammar)
      names = (before.grammar.nonterminals.map(&:name) + after.grammar.nonterminals.map(&:name)).uniq.sort
      changes = {} #: Hash[String, Hash[Symbol, Object?]]
      kinds = {} #: Hash[String, Array[String]]
      names.each do |name|
        before_symbol = before.grammar.symbol(name)
        after_symbol = after.grammar.symbol(name)
        first = set_change(before_sets, after_sets, before_symbol, after_symbol, :first)
        follow = set_change(before_sets, after_sets, before_symbol, after_symbol, :follow)
        nullable = nullable_change(before_sets, after_sets, before_symbol, after_symbol)
        next if set_change_empty?(first, follow, nullable)

        changes[name] = { first: first, follow: follow, nullable: nullable }
        kinds[name] = []
        kinds[name] << "first" unless first[:added].empty? && first[:removed].empty?
        kinds[name] << "follow" unless follow[:added].empty? && follow[:removed].empty?
        kinds[name] << "nullable" if nullable
      end
      [changes, kinds]
    end

    # @rbs (Analysis::Sets, Analysis::Sets, IR::GrammarSymbol?, IR::GrammarSymbol?, Symbol) ->
    #   Hash[Symbol, Array[String]]
    def set_change(before, after, before_symbol, after_symbol, kind)
      before_values = before_symbol&.nonterminal? ? before.public_send(kind, before_symbol) : [] #: Array[String]
      after_values = after_symbol&.nonterminal? ? after.public_send(kind, after_symbol) : [] #: Array[String]
      { added: after_values - before_values, removed: before_values - after_values }
    end

    # @rbs (Hash[Symbol, Array[String]], Hash[Symbol, Array[String]], Hash[Symbol, Object?]?) -> bool
    def set_change_empty?(first, follow, nullable)
      first_empty = first[:added].empty? && first[:removed].empty?
      follow_empty = follow[:added].empty? && follow[:removed].empty?
      first_empty && follow_empty && nullable.nil?
    end

    # @rbs (Analysis::Sets, Analysis::Sets, IR::GrammarSymbol?, IR::GrammarSymbol?) -> Hash[Symbol, Object?]?
    def nullable_change(before, after, before_symbol, after_symbol)
      return nil unless before_symbol || after_symbol

      old = before_symbol ? before.nullable?(before_symbol) : false
      current = after_symbol ? after.nullable?(after_symbol) : false
      return nil if old == current

      { before: old, after: current }
    end

    # @rbs (Hash[Integer, Array[String]], Hash[String, Array[String]], IR::Grammar) -> Hash[Integer, Array[String]]
    def merge_symbol_kinds(symbol_kinds, changed_kinds, grammar)
      result = symbol_kinds.transform_values(&:dup)
      changed_kinds.each do |name, kinds|
        id = grammar.symbol(name)&.id
        next unless id

        result[id] = (result.fetch(id, []) + kinds).uniq.sort
      end
      result
    end

    # @rbs (Hash[Symbol, Array[Hash[Symbol, Object?]]], IR::Grammar) -> Hash[String, Array[String]]
    def precedence_symbol_kinds(symbol_changes, grammar)
      result = {} #: Hash[String, Array[String]]
      symbol_changes.fetch(:changed).each do |record|
        before = record.fetch(:before)
        after = record.fetch(:after)
        next unless before.is_a?(Hash) && after.is_a?(Hash)
        next if before.fetch(:precedence) == after.fetch(:precedence)

        name = record.fetch(:id).to_s
        result[name] = ["precedence"] if grammar.symbol(name)
      end
      result
    end

    # @rbs (IR::Automaton) -> Array[String]
    def conflict_identities(automaton)
      automaton.states.flat_map do |state|
        state.conflicts.map { |conflict| conflict_identity(automaton.grammar, conflict) }
      end.uniq.sort
    end

    # @rbs (IR::Grammar, Hash[Symbol, Object?]) -> String
    def conflict_identity(grammar, conflict)
      type = conflict.fetch(:type).to_s.to_sym
      symbol = conflict.fetch(:symbol).to_s
      if type == :shift_reduce
        reduce = conflict.fetch(:reduce) #: Integer
        "shift_reduce:#{symbol}:#{production_shape(grammar, reduce)}"
      else
        reduction_ids = conflict.fetch(:reductions) #: Array[Integer]
        reductions = reduction_ids.map { |id| production_shape(grammar, id) }.sort
        "reduce_reduce:#{symbol}:#{reductions.join('|')}"
      end
    end

    # @rbs (IR::Grammar, Integer) -> String
    def production_shape(grammar, id)
      production = grammar.productions.fetch(id)
      lhs = grammar.symbol_by_id(production.lhs)&.name || production.lhs.to_s
      rhs = production.rhs.map { |symbol_id| grammar.symbol_by_id(symbol_id)&.name || symbol_id.to_s }
      "#{lhs}->#{rhs.join(' ')}"
    end

    # @rbs (Hash[Symbol, Object?], Array[String], Hash[Symbol, untyped]) -> void
    def apply_baseline(report, identities, settings)
      path = settings[:baseline]
      baseline = Impact::Baseline.new(path) if path
      baseline.write(identities) if baseline && settings[:update_baseline]
      return unless baseline

      known = baseline.conflicts
      conflicts = report.dig(:automaton, :conflicts, :added)
      return unless conflicts

      original_count = conflicts.length
      conflicts.reject! { |entry| known.include?(entry.fetch(:id)) }
      totals = report.fetch(:totals) #: Hash[Symbol, Integer]
      totals[:critical] -= original_count - conflicts.length
    end

    # @rbs (Hash[Symbol, Object?], String) -> void
    def write_impact_report(report, format)
      return @stdout.puts(JSON.pretty_generate(report)) if format == "json"

      symbols = report.fetch(:symbols) #: Array[untyped]
      warnings = report.fetch(:warnings) #: Array[String]
      @stdout.puts("impact mode=#{report.fetch(:mode)} symbols=#{symbols.length} " \
                   "affected_states=#{report.dig(:automaton, :affected_states).length}")
      warnings.each { |warning| @stdout.puts("warning: #{warning}") }
    end
  end
  # rubocop:enable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize
end
