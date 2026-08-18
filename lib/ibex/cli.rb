# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "version"
require_relative "error"
require_relative "configuration"
require_relative "messages"
require_relative "artifact_set"
require_relative "generation_input"
require_relative "generation_transaction"
require_relative "frontend/generation"
require_relative "ir/grammar_ir"
require_relative "ir/lexer_ir"
require_relative "ir/serialize"
require_relative "ir/automaton_ir"
require_relative "normalize"
require_relative "analysis"
require_relative "lalr/conflict"
require_relative "lalr/on_error_reductions"
require_relative "lalr/default_reductions"
require_relative "lalr/build_metrics"
require_relative "lalr/inadequacy_report"
require_relative "lalr/direct_lookaheads"
require_relative "lalr/ielr_partition"
require_relative "lalr/builder"
require_relative "lalr/unreachable_states"
# CLIImpact loads its analysis dependencies when the subcommand is selected.
require_relative "codegen/ruby"
require_relative "cli/counterexample_options"
require_relative "cli/generation_error_messages"
require_relative "cli/generation_artifacts"
require_relative "cli/outputs"

module Ibex
  CLI_FEATURE_ROOT = File.expand_path("cli", __dir__ || raise("CLI source directory is unavailable")) #: String
  autoload :CLIAmbiguity, File.join(CLI_FEATURE_ROOT, "ambiguity")
  autoload :CLIAnalysis, File.join(CLI_FEATURE_ROOT, "analysis")
  autoload :CLIImpact, File.join(CLI_FEATURE_ROOT, "impact")
  autoload :CLIBisonImport, File.join(CLI_FEATURE_ROOT, "bison_import")
  autoload :CLICoverage, File.join(CLI_FEATURE_ROOT, "coverage")
  autoload :CLIDebug, File.join(CLI_FEATURE_ROOT, "debug")
  autoload :CLIDiagnostics, File.join(CLI_FEATURE_ROOT, "diagnostics")
  autoload :CLIDocumentation, File.join(CLI_FEATURE_ROOT, "documentation")
  autoload :CLIErrorMessages, File.join(CLI_FEATURE_ROOT, "error_messages")
  autoload :CLIEquiv, File.join(CLI_FEATURE_ROOT, "equiv")
  autoload :CLIExplain, File.join(CLI_FEATURE_ROOT, "explain")
  autoload :CLIFormatting, File.join(CLI_FEATURE_ROOT, "formatting")
  autoload :CLIFix, File.join(CLI_FEATURE_ROOT, "fix")
  autoload :CLIFuzz, File.join(CLI_FEATURE_ROOT, "fuzz")
  autoload :CLIGrammarTests, File.join(CLI_FEATURE_ROOT, "grammar_tests")
  autoload :CLIIRTools, File.join(CLI_FEATURE_ROOT, "ir_tools")
  autoload :CLILSP, File.join(CLI_FEATURE_ROOT, "lsp")
  autoload :CLIRaccMigration, File.join(CLI_FEATURE_ROOT, "racc_migration")
  autoload :CLIReduce, File.join(CLI_FEATURE_ROOT, "reduce")
  autoload :CLISamples, File.join(CLI_FEATURE_ROOT, "samples")
  autoload :CLIVerify, File.join(CLI_FEATURE_ROOT, "verify")
  autoload :CLIWatch, File.join(CLI_FEATURE_ROOT, "watch")

  # @rbs!
  #   interface _CLIOutput
  #     def puts: (*Object?) -> Object?
  #     def write: (String) -> Object?
  #   end
  #   interface _CLIInput
  #     def read: () -> String
  #     def gets: () -> String?
  #   end
  #   type cli_options = {
  #     emit: String,
  #     mode: Symbol,
  #     table: Symbol,
  #     ?cst_trivia: Symbol,
  #     line_convert: bool,
  #     ?line_convert_all: bool,
  #     counterexample_max_tokens: Integer,
  #     counterexample_max_configurations: Integer,
  #     ?from: String,
  #     ?algorithm: Symbol,
  #     ?suggest_ielr: bool,
  #     ?entry_isolation: bool,
  #     ?ielr_strategy: Symbol,
  #     ?ielr_report: bool,
  #     ?remove_unreachable: bool,
  #     ?warnings: Array[Symbol],
  #     ?output: String,
  #     ?embedded: bool,
  #     ?debug: bool,
  #     ?verbose: bool,
  #     ?rbs: String | true,
  #     ?action_source: String | true,
  #     ?manifest: String | true,
  #     ?watch: bool,
  #     ?dot: String,
  #     ?mermaid: String,
  #     ?html: String,
  #     ?railroad: String,
  #     ?messages: String,
  #     ?messages_update: String | true,
  #     ?messages_algorithm_explicit: bool,
  #     ?sample_count: Integer,
  #     ?sample_seed: Integer,
  #     ?sample_max_tokens: Integer,
  #     ?sample_max_depth: Integer,
  #     ?sample_max_expansions: Integer,
  #     ?log_file: String,
  #     ?executable: String,
  #     ?frozen: bool,
  #     ?omit_actions: bool,
  #     ?superclass: String,
  #     ?verify_output: bool,
  #     ?check_only: bool,
  #     ?status: bool,
  #     ?profile: bool,
  #     ?debug_flags: String,
  #     ?version: bool,
  #     ?runtime_version: bool,
  #     ?copyright: bool,
  #     ?help: bool,
  #     ?explain_state: Integer,
  #     ?explain_token: String,
  #     ?explain_format: String,
  #     ?check_ambiguity: bool,
  #     ?check_format: String,
  #     ?fuzz_seed: Integer,
  #     ?fuzz_count: Integer,
  #     ?fuzz_max_tokens: Integer,
  #     ?fuzz_max_depth: Integer,
  #     ?fuzz_max_expansions: Integer,
  #     ?fuzz_max_actions: Integer,
  #     ?fuzz_max_stack: Integer,
  #     ?fuzz_coverage_guided: bool,
  #     ?fuzz_path_length: Integer,
  #     ?fuzz_against: String,
  #     ?fuzz_against_runtime: String,
  #     ?fuzz_against_timeout: Integer,
  #     ?fuzz_against_max_output: Integer,
  #     ?fuzz_max_reduction_trials: Integer,
  #     ?fuzz_regression_dir: String,
  #     ?fuzz_save_regression: bool,
  #     ?fuzz_format: String,
  #     ?reduce_command: String,
  #     ?reduce_mode: Symbol,
  #     ?reduce_max_trials: Integer,
  #     ?reduce_timeout: Integer,
  #     ?reduce_max_output_bytes: Integer,
  #     ?reduce_max_input_bytes: Integer,
  #     ?reduce_format: String
  #   }

  # Command-line pipeline coordinator.
  # rubocop:disable Metrics/ClassLength -- inline type contracts add lines without adding runtime responsibilities.
  class CLI
    FEATURE_LOADERS = {
      CLIAmbiguity: -> { CLIAmbiguity },
      CLIAnalysis: -> { CLIAnalysis },
      CLIImpact: -> { CLIImpact },
      CLIDiagnostics: -> { CLIDiagnostics },
      CLICoverage: -> { CLICoverage },
      CLIConfig: -> { CLIConfig },
      CLIDebug: -> { CLIDebug },
      CLIDocumentation: -> { CLIDocumentation },
      CLIErrorMessages: -> { CLIErrorMessages },
      CLIEquiv: -> { CLIEquiv },
      CLIExplain: -> { CLIExplain },
      CLIFormatting: -> { CLIFormatting },
      CLIFix: -> { CLIFix },
      CLIFuzz: -> { CLIFuzz },
      CLIGrammarTests: -> { CLIGrammarTests },
      CLILSP: -> { CLILSP },
      CLIBisonImport: -> { CLIBisonImport },
      CLIRaccMigration: -> { CLIRaccMigration },
      CLIReduce: -> { CLIReduce },
      CLISamples: -> { CLISamples },
      CLIVerify: -> { CLIVerify },
      CLIIRTools: -> { CLIIRTools },
      CLIWatch: -> { CLIWatch }
    }.freeze #: Hash[Symbol, ^() -> Module]

    # A fixed command object keeps dispatch explicit while feature modules stay lazy.
    class Command
      def initialize(feature, &handler)
        @feature = feature
        @handler = handler
        freeze
      end

      # @rbs (Ibex::CLI cli, Array[String] | String arguments) -> Integer?
      def call(cli, arguments)
        extension = FEATURE_LOADERS.fetch(@feature).call
        cli.extend(extension) unless cli.singleton_class.ancestors.include?(extension)
        cli.instance_exec(arguments, &@handler)
      end
    end

    COMMANDS = {
      "check" => Command.new(:CLIAmbiguity) { |arguments| run_check_command(arguments) },
      "diff" => Command.new(:CLIAnalysis) { |arguments| run_diff_command(arguments) },
      "impact" => Command.new(:CLIImpact) { |arguments| run_impact_command(arguments) },
      "diagnose" => Command.new(:CLIDiagnostics) { |arguments| run_diagnose_command(arguments) },
      "coverage" => Command.new(:CLICoverage) { |arguments| run_coverage_command(arguments) },
      "config" => Command.new(:CLIConfig) { |arguments| run_config_command(arguments) },
      "debug" => Command.new(:CLIDebug) { |arguments| run_debug_command(arguments) },
      "doc" => Command.new(:CLIDocumentation) { |arguments| run_documentation_command(arguments) },
      "errors" => Command.new(:CLIErrorMessages) { |arguments| run_error_messages_command(arguments) },
      "equiv" => Command.new(:CLIEquiv) { |arguments| run_equiv_command(arguments) },
      "explain" => Command.new(:CLIExplain) { |arguments| run_explain_command(arguments) },
      "fmt" => Command.new(:CLIFormatting) { |arguments| run_format_command(arguments) },
      "fix" => Command.new(:CLIFix) { |arguments| run_fix_command(arguments) },
      "fuzz" => Command.new(:CLIFuzz) { |arguments| run_fuzz_command(arguments) },
      "test" => Command.new(:CLIGrammarTests) { |arguments| run_grammar_tests_command(arguments) },
      "lsp" => Command.new(:CLILSP) { |arguments| run_lsp_command(arguments) },
      "import" => Command.new(:CLIBisonImport) { |arguments| run_bison_import_command(arguments) },
      "metrics" => Command.new(:CLIAnalysis) { |arguments| run_metrics_command(arguments) },
      "migrate-check" => Command.new(:CLIRaccMigration) { |arguments| run_migrate_check_command(arguments) },
      "migrate-harness" => Command.new(:CLIRaccMigration) { |arguments| run_migrate_harness_command(arguments) },
      "reduce" => Command.new(:CLIReduce) { |arguments| run_reduce_command(arguments) },
      "samples" => Command.new(:CLISamples) { |arguments| run_samples_command(arguments) },
      "verify" => Command.new(:CLIVerify) { |arguments| run_verify_command(arguments) },
      "validate-ir" => Command.new(:CLIIRTools) { |arguments| run_validate_ir_command(arguments) },
      "compare" => Command.new(:CLIIRTools) { |arguments| run_compare_command(arguments) }
    }.freeze #: Hash[String, Command]

    WATCH_COMMAND = Command.new(:CLIWatch) { |path| run_watch(path) }

    include CLICounterexampleOptions
    include CLIGenerationErrorMessages
    include CLIGenerationArtifacts
    include CLIOutputs

    # @rbs @stdout: _CLIOutput
    # @rbs @stderr: _CLIOutput
    # @rbs @options: cli_options
    # @rbs @language: String
    # @rbs @configuration_explicit_options: Hash[Symbol, bool]
    # @rbs @generation_grammar: IR::Grammar?
    # @rbs @generation_automaton: IR::Automaton?

    # rubocop:disable Layout/LineLength
    # @rbs (Array[String] arguments, ?stdin: _CLIInput, ?stdout: _CLIOutput, ?stderr: _CLIOutput, ?watch_sleeper: (^(Float) -> void)?, ?watch_iteration_hook: (^(Symbol, Integer, Array[String]) -> (Integer | Symbol | nil))?) -> Integer
    def self.start(arguments, stdin: $stdin, stdout: $stdout, stderr: $stderr, watch_sleeper: nil,
                   watch_iteration_hook: nil)
      new(
        stdin: stdin, stdout: stdout, stderr: stderr,
        watch_sleeper: watch_sleeper, watch_iteration_hook: watch_iteration_hook
      ).run(arguments)
    end

    # @rbs (?stdin: _CLIInput, stdout: _CLIOutput, stderr: _CLIOutput, ?watch_sleeper: (^(Float) -> void)?, ?watch_iteration_hook: (^(Symbol, Integer, Array[String]) -> (Integer | Symbol | nil))?) -> void
    def initialize(stdout:, stderr:, stdin: $stdin, watch_sleeper: nil, watch_iteration_hook: nil)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      # Watch debounce is sleeper-driven; no clock is injected.
      @watch_sleeper = watch_sleeper || ->(seconds) { sleep(seconds) }
      @watch_iteration_hook = watch_iteration_hook || ->(_event, _iteration, _paths) {}
      @language = Messages.language(ENV.fetch("IBEX_LANG", nil))
      @options = {
        emit: "ruby", mode: Configuration::Registry.fetch("grammar.mode").default,
        table: Configuration::Registry.fetch("table.representation").default, line_convert: true
      }
                 .merge(CLICounterexampleOptions::DEFAULTS)
      @configuration_explicit_options = {}
      @generation_grammar = nil
      @generation_automaton = @analysis_configuration = nil
    end
    # rubocop:enable Layout/LineLength

    # @rbs (Array[String] arguments) -> Integer
    def run(arguments)
      arguments = extract_language(arguments)
      @generation_grammar = nil
      @generation_automaton = @analysis_configuration = nil
      subcommand = dispatch_subcommand(arguments)
      return subcommand unless subcommand.nil?

      parser = option_parser
      remaining = parser.parse(arguments)
      validate_watch_information_options
      information = informational_result(parser)
      return information unless information.nil?

      validate_messages_options
      validate_generation_options
      path = input_path(remaining)
      validate_generation_paths!(path)
      if @options[:watch]
        run_watch_feature(path)
      else
        process_grammar(path)
      end
    rescue OptionParser::ParseError, Ibex::Error, SystemCallError, SystemStackError => e
      @stderr.puts(Messages.translate("cli.error", language: @language, detail: e.message))
      1
    end

    private

    # @rbs (Symbol name) -> void
    def mark_configuration_option(name)
      @configuration_explicit_options[name] = true
    end

    # OptionParser accepts a heterogeneous set of operation and configuration
    # values.  The CLIAdapter is the validation boundary for this dynamic map.
    # @rbs (Symbol name, untyped value) -> void
    def set_configuration_option(name, value)
      @options[name] = value
      mark_configuration_option(name)
    end

    # @rbs (String value) -> void
    def select_configuration_mode(value)
      set_configuration_option(:mode, value.to_sym)
    end

    # @rbs () -> Configuration::Resolver
    def effective_configuration
      grammar = @generation_grammar
      contract = grammar&.parser_contract
      @analysis_configuration || Configuration::CLIAdapter.new(
        @options, explicit_keys: @configuration_explicit_options.keys
      ).resolve(
        grammar: contract&.configuration_values || {},
        locations: contract&.configuration_locations || {}
      )
    end

    # Resolve a command-local legacy option hash without promoting it into the
    # reusable CLI instance's generation settings.
    # @rbs (Hash[Symbol, untyped] options, explicit_keys: Array[Symbol]) -> Configuration::Resolver
    def resolve_configuration_options(options, explicit_keys:)
      Configuration::CLIAdapter.new(options, explicit_keys: explicit_keys).resolve
    end

    # @rbs (Hash[Symbol, untyped] options, String name) -> untyped
    def local_configuration_value(options, name)
      explicit_keys = options.fetch(:configuration_explicit)
      resolve_configuration_options(options, explicit_keys: explicit_keys).value(name)
    end

    # @rbs (Hash[Symbol, untyped] options, Symbol name, untyped value) -> void
    def set_local_configuration_option(options, name, value)
      options[name] = value
      options.fetch(:configuration_explicit) << name
    end

    # Configuration values have already been validated by Configuration::Resolver;
    # callers narrow the value according to the option they are consuming.
    # @rbs (String name) -> untyped
    def configuration_value(name)
      effective_configuration.value(name)
    end

    # @rbs (Array[String] arguments) -> Array[String]
    def extract_language(arguments)
      remaining = [] #: Array[String]
      index = 0
      while index < arguments.length
        argument = arguments.fetch(index)
        if argument == "--lang"
          value = arguments[index + 1]
          raise OptionParser::MissingArgument, "--lang" unless value

          @language = Messages.language(value)
          index += 2
        elsif argument.start_with?("--lang=")
          value = argument.delete_prefix("--lang=")
          raise OptionParser::MissingArgument, "--lang" if value.empty?

          @language = Messages.language(value)
          index += 1
        else
          remaining << argument
          index += 1
        end
      end
      remaining
    end

    # @rbs (Array[String] arguments) -> Integer?
    def dispatch_subcommand(arguments)
      command = COMMANDS[arguments.first]
      return unless command

      command.call(self, arguments.drop(1))
    end

    # @rbs (Symbol feature) -> void
    def activate_cli_feature(feature)
      extension = FEATURE_LOADERS.fetch(feature).call
      extend extension unless singleton_class.ancestors.include?(extension)
    end

    # @rbs (String path) -> Integer
    def run_watch_feature(path)
      WATCH_COMMAND.call(self, path)
    end

    # @rbs () -> OptionParser
    def option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex [options] grammarfile"
        add_pipeline_options(options)
        add_output_options(options)
        add_error_messages_generation_option(options)
        add_compatibility_options(options)
        add_information_options(options)
        add_subcommand_help(options)
      end
    end

    # @rbs (OptionParser options) -> void
    def add_subcommand_help(options)
      options.separator("")
      options.separator("Subcommands:")
      options.separator("    check --ambiguity         search for ambiguity within explicit budgets")
      options.separator(CONFIG_SUBCOMMAND_HELP)
      options.separator("    debug AUTOMATON [TOKEN]  simulate validated Automaton IR tables")
      options.separator("    diagnose                  collect frontend diagnostics")
      options.separator("    diff OLD NEW              classify grammar and automaton changes")
      options.separator("    impact GRAMMAR            report grammar change propagation")
      options.separator("    doc                       render grammar documentation")
      options.separator("    errors --list|--update  list or update example-keyed syntax error messages")
      options.separator("    equiv LEFT RIGHT          search for bounded language differences")
      options.separator("    explain                   explain selected parser conflicts")
      options.separator("    fmt                       format grammar source")
      options.separator("    fix                       propose bounded-equivalent conflict repairs")
      options.separator("    fuzz                      run bounded grammar-derived differential fuzzing")
      options.separator("    test                      run grammar-declared source examples")
      options.separator("    lsp                       run the language server over stdio")
      options.separator("    import bison FILE         import Bison grammar structure for analysis")
      options.separator("    migrate-check             statically check a racc grammar migration")
      options.separator("    migrate-harness           generate a differential subprocess harness")
      options.separator("    metrics GRAMMAR           report deterministic grammar/table metrics")
      options.separator("    reduce                    delta-debug a failing token, line, or byte sequence")
      options.separator("    samples                   generate bounded terminal sentences")
      options.separator("    verify AUTOMATON         independently verify Automaton IR semantics")
      options.separator("    validate-ir FILE          validate the current IR document")
      options.separator("    compare BEFORE AFTER      compare current IR documents")
    end

    # @rbs (OptionParser options) -> void
    # rubocop:disable Metrics/MethodLength -- pipeline flags share one parser boundary.
    def add_pipeline_options(options)
      options.on("--emit=FORMAT", "ast, sets, lexer-ir, grammar-ir, automaton-ir, or ruby") do |value|
        @options[:emit] = value
      end
      options.on("--from=FORMAT", %w[grammar-ir automaton-ir], "resume from IR JSON") do |value|
        @options[:from] = value
      end
      options.on("--mode=MODE", %w[default extended], "grammar mode") { |value| select_configuration_mode(value) }
      options.on("--table=FORMAT", %w[plain compact], "parser table format") do |value|
        set_configuration_option(:table, value.to_sym)
      end
      options.on(
        "--cst-trivia=POLICY",
        Configuration::Registry::CLI_CST_TRIVIA_VALUES,
        "leading, balanced, drop, or attach (alias for leading)"
      ) do |value|
        set_configuration_option(:cst_trivia, value.to_sym)
      end
      options.on(
        "--algorithm=NAME", Configuration::Registry::CLI_ALGORITHM_VALUES, "parser construction algorithm"
      ) do |value|
        set_configuration_option(:algorithm, value.to_sym)
      end
      options.on("--ielr-strategy=NAME", %w[direct partition], "IELR construction strategy") do |value|
        @options[:ielr_strategy] = value.to_sym
      end
      options.on("--ielr-report", "report canonical-vs-IELR action differences") do
        @options[:ielr_report] = true
      end
      options.on("--remove-unreachable", "compact unreachable IELR states after resolution") do
        @options[:remove_unreachable] = true
      end
      options.on("--suggest-ielr", "check whether IELR removes unexpected LALR conflicts") do
        @options[:suggest_ielr] = true
      end
      options.on("--entry-isolation", "build independent state sets for each start symbol") do
        set_configuration_option(:entry_isolation, true)
      end
      options.on("--warnings=CATEGORIES", "all, error, all,error, or none") do |value|
        @options[:warnings] = warning_categories(value)
      end
      options.on("--watch", "regenerate file outputs when grammar sources change") { @options[:watch] = true }
    end
    # rubocop:enable Metrics/MethodLength

    # @rbs (OptionParser options) -> void
    def add_output_options(options)
      options.on("-o", "--output-file=FILE", "generated parser path") { |value| @options[:output] = value }
      options.on("-E", "--embedded", "embed the Pure Ruby runtime") do
        set_configuration_option(:embedded, true)
      end
      options.on("-t", "--debug", "generate a debug-capable parser") do
        set_configuration_option(:debug, true)
      end
      options.on("-g", "obsolete alias for --debug") do
        set_configuration_option(:debug, true)
      end
      options.on("-v", "--verbose", "write an automaton report") { @options[:verbose] = true }
      add_counterexample_options(options)
      add_signature_output_options(options)
      options.on("--manifest[=FILE]", "write a generation manifest (defaults beside parser)") do |value|
        @options[:manifest] = value || true
      end
      options.on("--dot=FILE", "write Graphviz DOT") { |value| @options[:dot] = value }
      options.on("--mermaid=FILE", "write a Mermaid flowchart") { |value| @options[:mermaid] = value }
      options.on("--html=FILE", "write a self-contained HTML report") { |value| @options[:html] = value }
      options.on("--railroad=FILE", "write a self-contained SVG railroad diagram") do |value|
        @options[:railroad] = value
      end
      options.on("-O", "--log-file=FILE", "automaton report path") do |value|
        @options[:verbose] = true
        @options[:log_file] = value
      end
      options.on("-e", "--executable [RUBY]", "add a shebang") do |value|
        set_configuration_option(:executable, value || "/usr/bin/env ruby")
      end
    end

    # @rbs (OptionParser options) -> void
    def add_signature_output_options(options)
      options.on("--rbs[=FILE]", "write an RBS signature (defaults beside parser)") do |value|
        @options[:rbs] = value || true
      end
      options.on("--action-source[=FILE]", "write static-check-only action Ruby (defaults beside parser)") do |value|
        @options[:action_source] = value || true
      end
    end

    # @rbs (OptionParser options) -> void
    def add_compatibility_options(options)
      options.on("-F", "--frozen", "emit frozen string literals") do
        set_configuration_option(:frozen, true)
      end
      options.on("--line-convert-all", "convert all source lines") do
        @options[:line_convert_all] = true
        set_configuration_option(:line_convert, true)
      end
      options.on("-l", "--no-line-convert", "use generated-file action lines") do
        @options[:line_convert_all] = false
        set_configuration_option(:line_convert, false)
      end
      options.on("-a", "--no-omit-actions", "generate implicit action methods") do
        set_configuration_option(:omit_actions, false)
      end
      options.on("--superclass=CLASS", "override parser superclass") do |value|
        set_configuration_option(:superclass, value)
      end
      options.on("--check", "verify generated parser content without rewriting") { @options[:verify_output] = true }
      options.on("-C", "--check-only", "check grammar and exit") { @options[:check_only] = true }
      options.on("-S", "--output-status", "show pipeline status") { @options[:status] = true }
      options.on("-P", "accept the compatibility profiling flag") { @options[:profile] = true }
      options.on("-D FLAGS", "accept internal compatibility flags") { |value| @options[:debug_flags] = value }
    end

    # @rbs (OptionParser options) -> void
    def add_information_options(options)
      options.on("--lang=LANG", "built-in diagnostic language (en or ja)") do |value|
        @language = Messages.language(value)
      end
      options.on("--version", "show version") { @options[:version] = true }
      options.on("--runtime-version", "show runtime version") { @options[:runtime_version] = true }
      options.on("--copyright", "show copyright") { @options[:copyright] = true }
      options.on("--help", "show help") { @options[:help] = true }
    end

    # @rbs @analysis_configuration: Configuration::Resolver?

    # @rbs (IR::Grammar grammar, ?options: Hash[Symbol, untyped], ?explicit_keys: Array[Symbol]) -> IR::Grammar
    def activate_analysis_grammar(grammar, options: @options, explicit_keys: @configuration_explicit_options.keys)
      adapter = Configuration::CLIAdapter.new(options, explicit_keys: explicit_keys)
      cli = adapter.configuration_values
      contract = grammar.parser_contract
      grammar_values = contract&.configuration_values || {}
      locations = contract&.configuration_locations || {}
      overrides = {} #: Hash[String, Configuration::config_value]
      algorithm = "parser.algorithm"
      if grammar_values.key?(algorithm) && cli.key?(algorithm) &&
         grammar_values.fetch(algorithm) != cli.fetch(algorithm)
        overrides[algorithm] = cli.delete(algorithm)
      end
      source_locations = {} #: Hash[Symbol, Hash[String, Location]]
      source_locations[:grammar] = locations unless locations.empty?
      configuration = Configuration::Resolver.new(
        grammar: grammar_values, cli: cli, analysis_overrides: overrides, locations: source_locations
      )
      @analysis_configuration = configuration
      active = noncanonical_analysis_grammar(grammar, configuration)
      @generation_grammar = active
      report_noncanonical_analysis(configuration)
      active
    end

    # @rbs (IR::Grammar grammar, Hash[Symbol, untyped] options, Array[Symbol] explicit_keys) ->
    #   [IR::Grammar, Symbol, IR::Automaton]
    def construct_analysis_automaton(grammar, options, explicit_keys)
      active = activate_analysis_grammar(grammar, options: options, explicit_keys: explicit_keys)
      algorithm = configuration_value("parser.algorithm") #: Symbol
      automaton = LALR::Builder.new(
        active, algorithm: algorithm, ielr_strategy: options.fetch(:ielr_strategy, :partition),
                remove_unreachable: options.fetch(:remove_unreachable, false),
                entry_isolation: configuration_value("parser.entries") == :isolated
      ).build
      [active, algorithm, automaton]
    end

    # @rbs (OptionParser parser) -> Integer?
    def informational_result(parser)
      return print_version if @options[:version] || @options[:runtime_version]
      return print_copyright if @options[:copyright]
      return print_help(parser) if @options[:help]

      nil
    end

    # @rbs (Array[String] remaining) -> String
    def input_path(remaining)
      path = remaining.first || raise(Ibex::Error, "(cli):1:1: grammar file is required")
      raise Ibex::Error, "(cli):1:1: only one grammar file may be specified" if remaining.length > 1

      path
    end

    # @rbs () -> void
    def validate_generation_options
      validate_automaton_construction_options

      validate_watch_generation_options if @options[:watch]
      validate_manifest_generation_options
      validate_action_source_generation_options
      validate_verification_generation_options
    end

    # @rbs () -> void
    def validate_automaton_construction_options
      return unless @options[:from] == "automaton-ir"

      if @configuration_explicit_options[:algorithm]
        raise Ibex::Error, "(cli):1:1: --algorithm cannot be combined with --from=automaton-ir"
      end
      return unless @configuration_explicit_options[:entry_isolation]

      raise Ibex::Error, "(cli):1:1: --entry-isolation cannot be combined with --from=automaton-ir"
    end

    # @rbs () -> void
    def validate_manifest_generation_options
      return unless @options[:manifest]

      raise Ibex::Error, "(cli):1:1: --manifest requires --emit=ruby" unless @options[:emit] == "ruby"
      raise Ibex::Error, "(cli):1:1: --manifest and --check-only cannot be combined" if @options[:check_only]
    end

    # @rbs () -> void
    def validate_action_source_generation_options
      return unless @options[:action_source]

      raise Ibex::Error, "(cli):1:1: --action-source requires --emit=ruby" unless @options[:emit] == "ruby"
      raise Ibex::Error, "(cli):1:1: --action-source and --check-only cannot be combined" if @options[:check_only]
    end

    # @rbs () -> void
    def validate_verification_generation_options
      return unless @options[:verify_output]

      raise Ibex::Error, "(cli):1:1: --check requires --emit=ruby" unless @options[:emit] == "ruby"
      raise Ibex::Error, "(cli):1:1: --check and --check-only cannot be combined" if @options[:check_only]
    end

    # @rbs () -> void
    def validate_watch_information_options
      return unless @options[:watch]
      return unless %i[version runtime_version copyright help].any? { |key| @options[key] }

      raise Ibex::Error, "(cli):1:1: --watch cannot be combined with information options"
    end

    # @rbs () -> void
    def validate_watch_generation_options
      raise Ibex::Error, "(cli):1:1: --watch cannot be combined with --from" if @options[:from]
      raise Ibex::Error, "(cli):1:1: --watch cannot be combined with --check" if @options[:verify_output]
      raise Ibex::Error, "(cli):1:1: --watch cannot be combined with --check-only" if @options[:check_only]
      return if @options[:emit] == "ruby"

      raise Ibex::Error, "(cli):1:1: --watch requires --emit=ruby with file outputs"
    end

    # @rbs (String input_path, ?source_paths: Array[String]) -> void
    def validate_generation_paths!(input_path, source_paths: [input_path])
      outputs = generation_paths(input_path).except(:input, :messages)
      paths = outputs.filter_map do |kind, path|
        [kind, path] if path
      end #: Array[[Symbol, String]]
      source_entries = source_paths.map.with_index do |path, index|
        [index.zero? ? :input : :"include_#{index}", path]
      end
      source_entries << [:messages, @options[:messages]] if @options[:messages]
      paths.concat(source_entries)
      collision = paths.combination(2).find do |pair|
        left = pair.fetch(0)
        right = pair.fetch(1)
        same_file_target?(left.fetch(1), right.fetch(1))
      end
      return unless collision

      labels = collision.map { |kind, path| "#{kind}=#{path}" }
      raise Ibex::Error, "(cli):1:1: paths must be distinct: #{labels.join(', ')}"
    end

    # @rbs (String left, String right) -> bool
    def same_file_target?(left, right)
      expanded_left = File.expand_path(left)
      expanded_right = File.expand_path(right)
      return true if expanded_left == expanded_right

      return true if File.exist?(expanded_left) && File.exist?(expanded_right) &&
                     File.identical?(expanded_left, expanded_right)

      portable_target_key(expanded_left) == portable_target_key(expanded_right)
    rescue SystemCallError
      expanded_left == expanded_right
    end

    # @rbs (String path) -> [String, String]
    def portable_target_key(path)
      canonical = canonical_target_path(path)
      basename = File.basename(canonical)
      folded = if basename.encoding == Encoding::UTF_8 && basename.valid_encoding?
                 basename.unicode_normalize(:nfc).downcase(:fold).unicode_normalize(:nfc)
               else
                 basename.downcase
               end
      [File.dirname(canonical), folded]
    end

    # @rbs (String path, ?Hash[String, bool] seen) -> String
    def canonical_target_path(path, seen = {})
      suffix = [] #: Array[String]
      cursor = File.expand_path(path)
      until File.exist?(cursor) || File.symlink?(cursor)
        parent = File.dirname(cursor)
        return path if parent == cursor

        suffix.unshift(File.basename(cursor))
        cursor = parent
      end
      if File.symlink?(cursor)
        raise Errno::ELOOP, cursor if seen[cursor]

        seen[cursor] = true
        target = File.expand_path(File.readlink(cursor), File.dirname(cursor))
        return File.join(canonical_target_path(target, seen), *suffix)
      end

      File.join(File.realpath(cursor), *suffix)
    end

    # @rbs (String input_path) -> Hash[Symbol, String?]
    def generation_paths(input_path)
      paths = { input: input_path, messages: @options[:messages] } #: Hash[Symbol, String?]
      if @options[:emit] == "ruby" && !@options[:check_only]
        output = @options[:output] || default_output_path(input_path, ".rb")
        paths[:parser] = output
        paths[:rbs] = rbs_output_path(output) if @options[:rbs]
        paths[:action_source] = action_source_output_path(output) if @options[:action_source]
        paths[:manifest] = manifest_output_path_for(output) if @options[:manifest]
      end
      unless @options[:verify_output]
        paths.merge!(dot: @options[:dot], mermaid: @options[:mermaid], html: @options[:html],
                     railroad: @options[:railroad])
        paths[:report] = @options[:log_file] || default_output_path(input_path, ".output") if @options[:verbose]
      end
      paths
    end

    # @rbs (String path) -> Integer
    def process_grammar(path)
      return process_ir(path) if @options[:from]

      begin_artifact_generation
      report_status("reading #{path}")
      resolution = resolve_grammar_path(path)
      @generation_inputs = @last_resolver.source_records
      @generation_sources = @generation_inputs.map(&:path)
      validate_generation_paths!(path, source_paths: resolution.files)
      return emit_ast(resolution.root) if @options[:emit] == "ast"

      grammar = Normalizer.new(resolution, mode: configuration_value("grammar.mode")).normalize
      dispatch_grammar(grammar, path)
    end

    # @rbs (String path) -> Frontend::Resolution
    def resolve_grammar_path(path)
      loader = Frontend::SourceLoader.new(record_reads: true)
      @last_resolver = Frontend::Resolver.new(path, mode: configuration_value("grammar.mode"), loader: loader)
      @last_resolver.resolve
    end

    # @rbs (String path) -> IR::Grammar
    def normalize_grammar_path(path)
      source = File.binread(path)
      if bison_source?(source)
        require_relative "bison_import"
        imported = BisonImport::Importer.new(source, file: path).run
        ast = Frontend::Parser.new(imported.source, file: path, mode: :extended).parse
        return Normalizer.new(ast, mode: :extended).normalize
      end

      Normalizer.new(resolve_grammar_path(path), mode: configuration_value("grammar.mode")).normalize
    end

    # @rbs (String source) -> bool
    def bison_source?(source)
      source.lines.count { |line| line.match?(%r{^\s*%%(?:\s|/|$)}) } >= 2
    end

    # @rbs (String path) -> Integer
    def process_ir(path)
      require_relative "ir/validator"

      begin_artifact_generation
      report_status("reading #{path}")
      source = File.binread(path)
      input = record_generation_input(path, source)
      validate_generation_paths!(path, source_paths: [input.path])
      value = IR::Validator.validate(source)
      expected = @options[:from] == "grammar-ir" ? IR::Grammar : IR::Automaton
      raise Ibex::Error, "#{path}:1:1: expected #{@options[:from]} input" unless value.is_a?(expected)

      return dispatch_grammar(value, path) if value.is_a?(IR::Grammar)
      return dispatch_automaton(value, path) if value.is_a?(IR::Automaton)

      raise Ibex::Error, "#{path}:1:1: expected #{@options[:from]} input"
    end

    # @rbs (IR::Grammar grammar, String path) -> Integer
    def dispatch_grammar(grammar, path)
      activate_generation_grammar(grammar)
      handle_grammar_warnings(grammar, path)
      if @options[:check_only]
        build_automaton(grammar, path) if @options[:warnings]&.include?(:error)
        return 0
      end

      write_railroad(grammar) unless @options[:verify_output]
      return emit_sets(grammar) if @options[:emit] == "sets"
      return emit_lexer(grammar) if @options[:emit] == "lexer-ir"
      return emit_grammar(grammar) if @options[:emit] == "grammar-ir"
      return emit_automaton(grammar, path) if @options[:emit] == "automaton-ir"
      return emit_ruby(grammar, path) if @options[:emit] == "ruby"

      raise Ibex::Error, "(cli):1:1: emit format #{@options[:emit].inspect} is not available yet"
    end

    # @rbs (IR::Automaton automaton, String path) -> Integer
    def dispatch_automaton(automaton, path)
      activate_generation_grammar(automaton.grammar)
      handle_grammar_warnings(automaton.grammar, path)
      return 0 if @options[:check_only]

      write_railroad(automaton.grammar) unless @options[:verify_output]
      return emit_sets(automaton.grammar) if @options[:emit] == "sets"
      return emit_lexer(automaton.grammar) if @options[:emit] == "lexer-ir"
      return emit_grammar(automaton.grammar) if @options[:emit] == "grammar-ir"
      return emit_loaded_automaton(automaton, path) if @options[:emit] == "automaton-ir"

      if @options[:emit] == "ruby"
        prepare_loaded_automaton(automaton, path)
        return generate_ruby(automaton, path)
      end

      raise Ibex::Error, "(cli):1:1: AST cannot be reconstructed from Automaton IR"
    end

    # @rbs (IR::Grammar grammar) -> void
    def activate_generation_grammar(grammar)
      @analysis_configuration = nil
      @generation_grammar = grammar
      effective_configuration
    end

    # @rbs (IR::Grammar grammar, Configuration::Resolver configuration) -> IR::Grammar
    def noncanonical_analysis_grammar(grammar, configuration)
      selection = configuration.fetch("parser.algorithm")
      return grammar if selection.canonical

      require_relative "configuration/analysis_grammar"
      algorithm = selection.value #: Symbol
      Configuration::AnalysisGrammar.for_algorithm(grammar, algorithm)
    end

    # @rbs (Configuration::Resolver configuration) -> void
    def report_noncanonical_analysis(configuration)
      selection = configuration.fetch("parser.algorithm")
      return if selection.canonical

      analysis = selection.to_h.fetch("analysis") #: Hash[String, Configuration::json_value]
      @stderr.puts(
        "noncanonical analysis configuration: parser.algorithm " \
        "declared=#{analysis.fetch('declared')} selected=#{analysis.fetch('selected')} " \
        "override=true canonical_generation=false"
      )
    end

    # @rbs () -> Integer
    def print_version
      @stdout.puts("ibex #{VERSION}")
      0
    end

    # @rbs (OptionParser parser) -> Integer
    def print_help(parser)
      @stdout.puts(parser)
      0
    end

    # @rbs () -> Integer
    def print_copyright
      @stdout.puts("Ibex #{VERSION} Copyright (c) 2026 Yudai Takada")
      0
    end

    # @rbs (Frontend::AST::Root ast) -> Integer
    def emit_ast(ast)
      @stdout.puts(JSON.pretty_generate(ast.to_h))
      0
    end

    # @rbs (IR::Grammar grammar) -> Integer
    def emit_grammar(grammar)
      finish_artifact_generation(@generation_sources)
      @stdout.write(IR::Serialize.dump(grammar))
      0
    end

    # @rbs (IR::Grammar grammar) -> Integer
    def emit_lexer(grammar)
      lexer = grammar.lexer
      raise Ibex::Error, "(cli):1:1: grammar does not declare a lexer" unless lexer

      finish_artifact_generation(@generation_sources)
      @stdout.write(IR::Serialize.dump(lexer))
      0
    end

    # @rbs (IR::Grammar grammar) -> Integer
    def emit_sets(grammar)
      sets = Analysis::Sets.new(grammar)
      nonterminals = grammar.nonterminals.sort_by(&:name)
      output = {
        nullable: nonterminals.filter_map { |symbol| symbol.name if sets.nullable?(symbol) },
        first: nonterminals.to_h { |symbol| [symbol.name, sets.first(symbol).sort] },
        follow: nonterminals.to_h { |symbol| [symbol.name, sets.follow(symbol).sort] }
      }
      finish_artifact_generation(@generation_sources)
      @stdout.puts(JSON.pretty_generate(output))
      0
    end

    # @rbs (IR::Grammar grammar, String input_path) -> Integer
    def emit_automaton(grammar, input_path)
      automaton = build_automaton(grammar, input_path)
      finish_artifact_generation(@generation_sources)
      @stdout.write(IR::Serialize.dump(automaton))
      0
    end

    # @rbs (IR::Grammar grammar, String input_path) -> Integer
    def emit_ruby(grammar, input_path)
      automaton = build_automaton(grammar, input_path)
      generate_ruby(automaton, input_path)
    end

    # @rbs (IR::Automaton automaton, String input_path) -> Integer
    def generate_ruby(automaton, input_path)
      @generation_automaton = automaton
      line_mapping = configuration_value("source.line_mapping") #: Symbol
      executable = configuration_value("build.executable") #: String?
      table = configuration_value("table.representation") #: Symbol | String
      embedded = configuration_value("runtime.embedded") #: bool
      debug = configuration_value("build.debug") #: bool
      omit_action_call = configuration_value("actions.omit_calls") #: bool?
      superclass = configuration_value("parser.superclass") #: String?
      cst_trivia = configuration_value("cst.trivia") #: Symbol | String
      source = Codegen::Ruby.new(
        automaton, table: table, embedded: embedded,
                   line_convert: line_mapping != :none, debug: debug,
                   line_convert_all: line_mapping == :all,
                   omit_action_call: omit_action_call, superclass: superclass,
                   executable: executable, cst_trivia: cst_trivia,
                   error_messages: configured_error_messages(automaton)
      ).generate
      output_path = @options[:output] || default_output_path(input_path, ".rb")
      action_source = action_source_source(automaton) if @options[:action_source]
      write_action_source(output_path, action_source) if action_source
      register_artifact(:parser, output_path, source, mode: (0o755 if executable), status: true)
      write_rbs(automaton, output_path) if @options[:rbs]
      finish_artifact_generation(@generation_sources)
    end

    # @rbs (IR::Automaton automaton, String output_path, String source, String? action_source) -> Integer
    def verify_generated_outputs(automaton, output_path, source, action_source)
      verify_file(output_path, source, "parser")
      verify_file(rbs_output_path(output_path), rbs_source(automaton), "RBS signature") if @options[:rbs]
      verify_file(action_source_output_path(output_path), action_source, "action source") if action_source
      report_status("verified #{output_path}")
      0
    end

    # @rbs (String path, String source, String label) -> void
    def verify_file(path, source, label)
      raise Ibex::Error, "#{path}:1:1: generated #{label} is missing" unless File.exist?(path)
      return if File.binread(path) == source

      raise Ibex::Error, "#{path}:1:1: generated #{label} is stale; regenerate it with the same options"
    end

    # @rbs (IR::Automaton automaton, String output_path) -> void
    def write_rbs(automaton, output_path)
      path = rbs_output_path(output_path)
      source = rbs_source(automaton)
      register_artifact(:rbs, path, source, status: true)
    end

    # @rbs (String output_path) -> String
    def rbs_output_path(output_path)
      configured_path = @options[:rbs]
      path = configured_path == true ? default_output_path(output_path, ".rbs") : configured_path
      raise ArgumentError, "RBS output path is required" unless path.is_a?(String)

      path
    end

    # @rbs (IR::Automaton automaton) -> String
    def rbs_source(automaton)
      require_relative "codegen/rbs"
      superclass = configuration_value("parser.superclass") #: String?
      omit_action_call = configuration_value("actions.omit_calls") #: bool?
      Codegen::RBS.new(
        automaton, superclass: superclass, omit_action_call: omit_action_call
      ).generate
    end

    # @rbs (String output_path, String source) -> void
    def write_action_source(output_path, source)
      path = action_source_output_path(output_path)
      register_artifact(:action_source, path, source, status: true)
    end

    # @rbs (String output_path) -> String
    def action_source_output_path(output_path)
      configured_path = @options[:action_source]
      path = configured_path == true ? default_output_path(output_path, ".actions.rb") : configured_path
      raise Ibex::Error, "(cli):1:1: action source output path is required" unless path.is_a?(String) && !path.empty?

      path
    end

    # @rbs (IR::Automaton automaton) -> String
    def action_source_source(automaton)
      require_relative "codegen/action_source"
      Codegen::ActionSource.new(
        automaton, omit_action_call: configuration_value("actions.omit_calls")
      ).generate
    end

    # @rbs (IR::Automaton automaton, String input_path) -> Integer
    def emit_loaded_automaton(automaton, input_path)
      prepare_loaded_automaton(automaton, input_path)
      finish_artifact_generation(@generation_sources)
      @stdout.write(IR::Serialize.dump(automaton))
      0
    end

    # @rbs (IR::Grammar grammar, String input_path) -> IR::Automaton
    def build_automaton(grammar, input_path)
      algorithm = configuration_value("parser.algorithm")
      report_status("building #{algorithm} automaton")
      automaton = LALR::Builder.new(
        grammar, algorithm: algorithm, ielr_strategy: @options.fetch(:ielr_strategy, :partition),
                 remove_unreachable: @options.fetch(:remove_unreachable, false),
                 entry_isolation: configuration_value("parser.entries") == :isolated
      ).build
      write_ielr_report(grammar, automaton) if @options[:ielr_report]
      report_conflicts(automaton, input_path)
      suggest_ielr(automaton, input_path)
      write_report(automaton, input_path) if @options[:verbose] && !@options[:verify_output]
      write_visualizations(automaton) unless @options[:verify_output]
      automaton
    end

    # @rbs (IR::Grammar grammar, IR::Automaton automaton) -> void
    def write_ielr_report(grammar, automaton)
      canonical = LALR::Builder.new(grammar, algorithm: :lr1).build
      @stdout.write(LALR::InadequacyReport.new(canonical, automaton).to_json)
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def prepare_loaded_automaton(automaton, input_path)
      report_conflicts(automaton, input_path)
      suggest_ielr(automaton, input_path)
      write_report(automaton, input_path) if @options[:verbose] && !@options[:verify_output]
      write_visualizations(automaton) unless @options[:verify_output]
    end

    # @rbs (IR::Automaton automaton) -> void
    def write_visualizations(automaton)
      dot_path = @options[:dot]
      mermaid_path = @options[:mermaid]
      html_path = @options[:html]
      if dot_path
        require_relative "codegen/dot"
        register_artifact(:dot, dot_path, Codegen::Dot.render(automaton))
      end
      if mermaid_path
        require_relative "codegen/mermaid"
        register_artifact(:mermaid, mermaid_path, Codegen::Mermaid.render(automaton))
      end
      return unless html_path

      require_relative "codegen/html"
      register_artifact(:html, html_path, Codegen::HTML.render(automaton))
    end

    # @rbs (IR::Grammar grammar) -> void
    def write_railroad(grammar)
      path = @options[:railroad]
      return unless path

      require_relative "codegen/railroad"
      register_artifact(:railroad, path, Codegen::Railroad.render(grammar))
    end

    # @rbs (String output_path) -> String
    def manifest_output_path_for(output_path)
      configured = @options[:manifest]
      return configured if configured.is_a?(String) && !configured.empty?

      default_output_path(output_path, ".ibex.json")
    end
  end
  CONFIG_SUBCOMMAND_HELP = [
    "    coverage                  collect, merge, or check runtime coverage",
    "    config                    explain effective configuration without running user code"
  ].join("\n").freeze #: String
  autoload :CLIConfig, File.join(CLI_FEATURE_ROOT, "config")
  # rubocop:enable Metrics/ClassLength
end
