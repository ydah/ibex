# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../fix"

module Ibex
  # CLI entry point for bounded conflict-repair proposals.
  # rubocop:disable Metrics/ModuleLength -- CLI option wiring and output projections share one closed contract.
  module CLIFix
    # @rbs!
    #   type fix_options = Hash[Symbol, untyped]
    #   private def normalize_grammar_path: (String) -> IR::Grammar
    #   private def activate_cli_feature: (Symbol) -> void
    #   private def configuration_value: (String) -> untyped
    #   private def set_configuration_option: (Symbol, Object?) -> void
    #   private def local_configuration_value: (Hash[Symbol, Object?], String) -> Object?
    #   private def set_local_configuration_option: (Hash[Symbol, Object?], Symbol, Object?) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_fix_command(arguments)
      settings = fix_options(arguments)
      if settings[:help]
        @stdout.puts(settings.fetch(:help))
        return 0
      end
      paths = settings.fetch(:paths)
      raise Ibex::Error, "(fix):1:1: fix requires exactly one grammar source file" unless paths.length == 1

      path = paths.fetch(0)
      source, fixer = prepare_fixer(path, settings)
      report = fixer.run
      apply_fix!(path, source, report, fixer, settings.fetch(:apply)) if settings[:apply]
      write_fix_report(report, settings.fetch(:format))
      proposals = report.fetch(:proposals) #: Array[Hash[Symbol, untyped]]
      proposals.empty? ? 1 : 0
    rescue Fix::BudgetExceeded => e
      report = { ibex_report: "fix", schema_version: Fix::SCHEMA_VERSION }.merge(e.details)
      write_fix_report(report, settings&.fetch(:format) || "json")
      2
    end

    # @rbs (String path, Hash[Symbol, untyped] settings) -> [String, Fix]
    def prepare_fixer(path, settings)
      source = File.binread(path)
      if BisonImport.bison_source?(source)
        imported = BisonImport::Importer.new(source, file: path).run
        unless imported.structurally_complete?
          names = imported.structural_unsupported.map(&:name).uniq.sort.join(", ")
          raise Ibex::Error,
                "(fix):1:1: Bison import is structurally incomplete due to: #{names}"
        end
        raise Ibex::Error,
              "(fix):1:1: import Bison source to a canonical analysis file before requesting source repairs"
      end
      grammar = normalize_grammar_path(path)
      grammar, algorithm, automaton = fixer_construction(grammar, settings)
      message_file = settings[:messages]
      messages = ErrorMessages.load(message_file) if message_file
      mode = configuration_value("grammar.mode") #: Symbol
      fixer = Fix.new(
        source,
        file: path, grammar: grammar, automaton: automaton,
        algorithm: algorithm, mode: mode,
        state: settings[:state], conflict_index: settings[:conflict_index],
        max_candidates: settings.fetch(:max_candidates), max_builds: settings.fetch(:max_builds),
        equiv_samples: settings.fetch(:equiv_samples),
        equiv_max_tokens: settings.fetch(:equiv_max_tokens),
        equiv_max_configurations: settings.fetch(:equiv_max_configurations),
        verify_max_states: settings.fetch(:verify_max_states),
        verify_max_items: settings.fetch(:verify_max_items),
        messages: messages, message_file: message_file
      )
      [source, fixer]
    end

    # Keep command-local construction settings separate from reusable CLI state.
    # @rbs (Array[String] arguments) -> Hash[Symbol, untyped]
    def fix_options(arguments)
      settings = {
        paths: [], algorithm: Configuration::Registry.fetch("parser.algorithm").default,
        mode: Configuration::Registry.fetch("grammar.mode").default, format: "json",
        max_candidates: 32, max_builds: 32, equiv_samples: 100,
        equiv_max_tokens: 8, equiv_max_configurations: 50_000,
        verify_max_states: 100_000, verify_max_items: 1_000_000, configuration_explicit: []
      } #: Hash[Symbol, untyped]
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex fix [options] GRAMMAR"
        add_fix_target_options(options, settings)
        add_fix_budget_options(options, settings)
        add_fix_parser_options(options, settings)
        options.on("--apply[=ID]", "atomically apply one safe source proposal") do |value|
          settings[:apply] = value || true
        end
        options.on("--messages=FILE", "measure effects on an error-message catalog") do |value|
          settings[:messages] = value
        end
        options.on("--format=FORMAT", %w[json text], "json or text") { |value| settings[:format] = value }
        options.on("--help", "show help") { settings[:help] = options.to_s }
      end
      settings[:paths] = parser.parse(arguments)
      settings[:algorithm] = local_configuration_value(settings, "parser.algorithm")
      settings
    end

    # @rbs (OptionParser options, Hash[Symbol, untyped] settings) -> void
    def add_fix_parser_options(options, settings)
      options.on(
        "--algorithm=NAME", Configuration::Registry::CLI_ALGORITHM_VALUES, "current construction algorithm"
      ) { |value| set_local_configuration_option(settings, :algorithm, value.to_sym) }
      options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
        set_local_configuration_option(settings, :mode, value.to_sym)
        set_configuration_option(:mode, value.to_sym)
      end
    end

    # @rbs (OptionParser options, Hash[Symbol, untyped] settings) -> void
    def add_fix_target_options(options, settings)
      options.on("--state=N", Integer, "target state (default first unresolved conflict)") do |value|
        raise OptionParser::InvalidArgument, "--state must be nonnegative" if value.negative?

        settings[:state] = value
      end
      options.on("--conflict-index=N", Integer, "target conflict index within the state") do |value|
        raise OptionParser::InvalidArgument, "--conflict-index must be nonnegative" if value.negative?

        settings[:conflict_index] = value
      end
    end

    # @rbs (OptionParser options, Hash[Symbol, untyped] settings) -> void
    def add_fix_budget_options(options, settings)
      {
        "max-candidates" => :max_candidates,
        "max-builds" => :max_builds,
        "equiv-samples" => :equiv_samples,
        "equiv-max-tokens" => :equiv_max_tokens,
        "equiv-max-configurations" => :equiv_max_configurations,
        "verify-max-states" => :verify_max_states,
        "verify-max-items" => :verify_max_items
      }.each do |name, key|
        options.on("--#{name}=N", Integer, "positive bounded-search limit") do |value|
          raise OptionParser::InvalidArgument, "--#{name} must be positive" unless value.positive?

          settings[key] = value
        end
      end
    end

    # @rbs (IR::Grammar grammar, Hash[Symbol, untyped] settings) -> [IR::Grammar, Symbol, IR::Automaton]
    def fixer_construction(grammar, settings)
      explicit_keys = settings.fetch(:configuration_explicit) & [:algorithm]
      construct_analysis_automaton(grammar, { algorithm: settings.fetch(:algorithm) }, explicit_keys)
    end

    # @rbs!
    #   private def construct_analysis_automaton: (IR::Grammar, Hash[Symbol, Object?], Array[Symbol]) ->
    #     [IR::Grammar, Symbol, IR::Automaton]

    # @rbs (String path, String original, Hash[Symbol, untyped] report, Fix fixer, String | true selector) -> void
    def apply_fix!(path, original, report, fixer, selector)
      proposal = selected_fix_proposal(report.fetch(:proposals), selector)
      unless proposal.fetch(:applyable)
        raise Ibex::Error, "(fix):1:1: proposal #{proposal.fetch(:id)} changes invocation options, not source"
      end
      if File.symlink?(path) || File.stat(path).nlink > 1
        raise Ibex::Error, "(fix):1:1: --apply refuses symlink aliases and files with multiple hard links"
      end

      replacement = fixer.sources.fetch(proposal.fetch(:id))
      activate_cli_feature(:CLIFormatting)
      results = [{
        path: path, label: path, source: original, formatted: replacement
      }]
      targets = formatting_targets(results)
      transactionally_write_formatted(targets)
      report[:applied] = proposal.fetch(:id)
    end

    # @rbs (Array[Hash[Symbol, untyped]] proposals, String | true selector) -> Hash[Symbol, untyped]
    def selected_fix_proposal(proposals, selector)
      proposal = if selector == true
                   proposals.find { |entry| entry.fetch(:applyable) }
                 else
                   proposals.find { |entry| entry.fetch(:id) == selector }
                 end
      proposal || raise(Ibex::Error, "(fix):1:1: no matching applyable safe proposal")
    end

    # @rbs (Hash[Symbol, untyped] report, String format) -> void
    def write_fix_report(report, format)
      if format == "json"
        @stdout.puts(JSON.pretty_generate(report))
        return
      end

      @stdout.puts("result=#{report.fetch(:result)} proposals=#{report.fetch(:proposals, []).length}")
      report.fetch(:proposals, []).each do |proposal|
        @stdout.puts("#{proposal.fetch(:id)} #{proposal.fetch(:description)}")
      end
      @stdout.puts(report.fetch(:statement, Equiv::CAVEAT))
    end

    # @rbs!
    #   private def formatting_targets: (Array[Hash[Symbol, untyped]]) -> Array[Hash[Symbol, untyped]]
    #   private def transactionally_write_formatted: (Array[Hash[Symbol, untyped]]) -> void
  end
  # rubocop:enable Metrics/ModuleLength
end
