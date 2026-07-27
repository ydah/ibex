# frozen_string_literal: true

require "json"
require "optparse"
require_relative "version"
require_relative "error"
require_relative "artifact_set"
require_relative "generation_input"
require_relative "generation_manifest"
require_relative "generation_transaction"
require_relative "frontend"
require_relative "ir"
require_relative "normalize"
require_relative "analysis"
require_relative "lalr"
require_relative "codegen/ruby"
require_relative "cli/counterexample_options"
require_relative "cli/generation_error_messages"
require_relative "cli/generation_artifacts"
require_relative "cli/outputs"

module Ibex
  CLI_FEATURE_ROOT = File.expand_path("cli", __dir__ || raise("CLI source directory is unavailable")) #: String
  autoload :CLIAmbiguity, File.join(CLI_FEATURE_ROOT, "ambiguity")
  autoload :CLICoverage, File.join(CLI_FEATURE_ROOT, "coverage")
  autoload :CLIDebug, File.join(CLI_FEATURE_ROOT, "debug")
  autoload :CLIDiagnostics, File.join(CLI_FEATURE_ROOT, "diagnostics")
  autoload :CLIDocumentation, File.join(CLI_FEATURE_ROOT, "documentation")
  autoload :CLIErrorMessages, File.join(CLI_FEATURE_ROOT, "error_messages")
  autoload :CLIExplain, File.join(CLI_FEATURE_ROOT, "explain")
  autoload :CLIFormatting, File.join(CLI_FEATURE_ROOT, "formatting")
  autoload :CLIGrammarTests, File.join(CLI_FEATURE_ROOT, "grammar_tests")
  autoload :CLIIRTools, File.join(CLI_FEATURE_ROOT, "ir_tools")
  autoload :CLILSP, File.join(CLI_FEATURE_ROOT, "lsp")
  autoload :CLIRaccMigration, File.join(CLI_FEATURE_ROOT, "racc_migration")
  autoload :CLISamples, File.join(CLI_FEATURE_ROOT, "samples")
  autoload :CLIWatch, File.join(CLI_FEATURE_ROOT, "watch")

  # @rbs!
  #   interface _CLIOutput
  #     def puts: (*untyped) -> untyped
  #     def write: (String) -> untyped
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
  #     ?entry_isolation: bool,
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
  #     ?check_format: String
  #   }

  # Command-line pipeline coordinator.
  # rubocop:disable Metrics/ClassLength -- inline type contracts add lines without adding runtime responsibilities.
  class CLI
    # @rbs!
    #   private def run_watch: (String) -> Integer

    SUBCOMMAND_HANDLERS = {
      "check" => %i[CLIAmbiguity run_check_command],
      "diagnose" => %i[CLIDiagnostics run_diagnose_command],
      "coverage" => %i[CLICoverage run_coverage_command],
      "debug" => %i[CLIDebug run_debug_command],
      "doc" => %i[CLIDocumentation run_documentation_command],
      "errors" => %i[CLIErrorMessages run_error_messages_command],
      "explain" => %i[CLIExplain run_explain_command],
      "fmt" => %i[CLIFormatting run_format_command],
      "test" => %i[CLIGrammarTests run_grammar_tests_command],
      "lsp" => %i[CLILSP run_lsp_command],
      "migrate-check" => %i[CLIRaccMigration run_migrate_check_command],
      "migrate-harness" => %i[CLIRaccMigration run_migrate_harness_command],
      "samples" => %i[CLISamples run_samples_command],
      "validate-ir" => %i[CLIIRTools run_validate_ir_command],
      "compare" => %i[CLIIRTools run_compare_command],
      "migrate-ir" => %i[CLIIRTools run_migrate_ir_command]
    }.freeze #: Hash[String, [Symbol, Symbol]]

    include CLICounterexampleOptions
    include CLIGenerationErrorMessages
    include CLIGenerationArtifacts
    include CLIOutputs

    # @rbs @stdout: _CLIOutput
    # @rbs @stderr: _CLIOutput
    # @rbs @options: cli_options

    # rubocop:disable Layout/LineLength
    # @rbs (Array[String] arguments, ?stdin: _CLIInput, ?stdout: _CLIOutput, ?stderr: _CLIOutput, ?watch_clock: (^() -> Float)?, ?watch_sleeper: (^(Float) -> void)?, ?watch_iteration_hook: (^(Symbol, Integer, Array[String]) -> (Integer | Symbol | nil))?) -> Integer
    def self.start(arguments, stdin: $stdin, stdout: $stdout, stderr: $stderr, watch_clock: nil, watch_sleeper: nil,
                   watch_iteration_hook: nil)
      new(
        stdin: stdin, stdout: stdout, stderr: stderr, watch_clock: watch_clock,
        watch_sleeper: watch_sleeper, watch_iteration_hook: watch_iteration_hook
      ).run(arguments)
    end

    # @rbs (?stdin: _CLIInput, stdout: _CLIOutput, stderr: _CLIOutput, ?watch_clock: (^() -> Float)?, ?watch_sleeper: (^(Float) -> void)?, ?watch_iteration_hook: (^(Symbol, Integer, Array[String]) -> (Integer | Symbol | nil))?) -> void
    def initialize(stdout:, stderr:, stdin: $stdin, watch_clock: nil, watch_sleeper: nil, watch_iteration_hook: nil)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @watch_clock = watch_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @watch_sleeper = watch_sleeper || ->(seconds) { sleep(seconds) }
      @watch_iteration_hook = watch_iteration_hook || ->(_event, _iteration, _paths) {}
      @options = { emit: "ruby", mode: :racc, table: :compact, line_convert: true }
                 .merge(CLICounterexampleOptions::DEFAULTS)
    end
    # rubocop:enable Layout/LineLength

    # @rbs (Array[String] arguments) -> Integer
    def run(arguments)
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
        activate_cli_feature(:CLIWatch)
        run_watch(path)
      else
        process_grammar(path)
      end
    rescue OptionParser::ParseError, Ibex::Error, SystemCallError, SystemStackError => e
      @stderr.puts(e.message)
      1
    end

    private

    # @rbs (Array[String] arguments) -> Integer?
    def dispatch_subcommand(arguments)
      definition = SUBCOMMAND_HANDLERS[arguments.first]
      return unless definition

      feature, handler = definition
      activate_cli_feature(feature)
      send(handler, arguments.drop(1))
    end

    # @rbs (Symbol feature) -> void
    def activate_cli_feature(feature)
      extension = Ibex.const_get(feature)
      extend extension unless singleton_class.ancestors.include?(extension)
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
        options.separator("")
        options.separator("Subcommands:")
        options.separator("    check --ambiguity         search for ambiguity within explicit budgets")
        options.separator("    coverage                  collect, merge, or check runtime coverage")
        options.separator("    debug AUTOMATON [TOKEN]  simulate validated Automaton IR tables")
        options.separator("    diagnose                  collect frontend diagnostics")
        options.separator("    doc                       render grammar documentation")
        options.separator("    errors --list|--update  list or update example-keyed syntax error messages")
        options.separator("    explain                   explain selected parser conflicts")
        options.separator("    fmt                       format grammar source")
        options.separator("    test                      run grammar-declared source examples")
        options.separator("    lsp                       run the language server over stdio")
        options.separator("    migrate-check             statically check a racc grammar migration")
        options.separator("    migrate-harness           generate a differential subprocess harness")
        options.separator("    samples                   generate bounded terminal sentences")
        options.separator("    validate-ir FILE          validate a versioned IR document")
        options.separator("    compare BEFORE AFTER      compare two versioned IR documents")
        options.separator("    migrate-ir INPUT --to=2   migrate a versioned IR document")
      end
    end

    # @rbs (OptionParser options) -> void
    def add_pipeline_options(options)
      options.on("--emit=FORMAT", "ast, sets, lexer-ir, grammar-ir, automaton-ir, or ruby") do |value|
        @options[:emit] = value
      end
      options.on("--from=FORMAT", %w[grammar-ir automaton-ir], "resume from IR JSON") do |value|
        @options[:from] = value
      end
      options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
      options.on("--table=FORMAT", %w[plain compact], "parser table format") do |value|
        @options[:table] = value.to_sym
      end
      options.on("--cst-trivia=POLICY", %w[attach drop], "retain or discard lexer trivia in CST output") do |value|
        @options[:cst_trivia] = value.to_sym
      end
      options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "parser construction algorithm") do |value|
        @options[:algorithm] = value.to_sym
      end
      options.on("--entry-isolation", "build independent state sets for each start symbol") do
        @options[:entry_isolation] = true
      end
      options.on("--warnings=CATEGORIES", "all, error, all,error, or none") do |value|
        @options[:warnings] = warning_categories(value)
      end
      options.on("--watch", "regenerate file outputs when grammar sources change") { @options[:watch] = true }
    end

    # @rbs (OptionParser options) -> void
    def add_output_options(options)
      options.on("-o", "--output-file=FILE", "generated parser path") { |value| @options[:output] = value }
      options.on("-E", "--embedded", "embed the Pure Ruby runtime") { @options[:embedded] = true }
      options.on("-t", "--debug", "generate a debug-capable parser") { @options[:debug] = true }
      options.on("-g", "obsolete alias for --debug") { @options[:debug] = true }
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
        @options[:executable] = value || "/usr/bin/env ruby"
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
      options.on("-F", "--frozen", "emit frozen string literals") { @options[:frozen] = true }
      options.on("--line-convert-all", "convert all source lines") do
        @options[:line_convert] = true
        @options[:line_convert_all] = true
      end
      options.on("-l", "--no-line-convert", "use generated-file action lines") do
        @options[:line_convert] = false
        @options[:line_convert_all] = false
      end
      options.on("-a", "--no-omit-actions", "generate implicit action methods") { @options[:omit_actions] = false }
      options.on("--superclass=CLASS", "override parser superclass") { |value| @options[:superclass] = value }
      options.on("--check", "verify generated parser content without rewriting") { @options[:verify_output] = true }
      options.on("-C", "--check-only", "check grammar and exit") { @options[:check_only] = true }
      options.on("-S", "--output-status", "show pipeline status") { @options[:status] = true }
      options.on("-P", "accept the compatibility profiling flag") { @options[:profile] = true }
      options.on("-D FLAGS", "accept internal compatibility flags") { |value| @options[:debug_flags] = value }
    end

    # @rbs (OptionParser options) -> void
    def add_information_options(options)
      options.on("--version", "show version") { @options[:version] = true }
      options.on("--runtime-version", "show runtime version") { @options[:runtime_version] = true }
      options.on("--copyright", "show copyright") { @options[:copyright] = true }
      options.on("--help", "show help") { @options[:help] = true }
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
      if @options[:entry_isolation] && @options[:from] == "automaton-ir"
        raise Ibex::Error, "(cli):1:1: --entry-isolation cannot be combined with --from=automaton-ir"
      end

      validate_watch_generation_options if @options[:watch]
      validate_manifest_generation_options
      validate_action_source_generation_options
      validate_verification_generation_options
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

      grammar = Normalizer.new(resolution, mode: @options[:mode]).normalize
      dispatch_grammar(grammar, path)
    end

    # @rbs (String path) -> Frontend::Resolution
    def resolve_grammar_path(path)
      loader = Frontend::SourceLoader.new(record_reads: true)
      @last_resolver = Frontend::Resolver.new(path, mode: @options[:mode], loader: loader)
      @last_resolver.resolve
    end

    # @rbs (String path) -> IR::Grammar
    def normalize_grammar_path(path)
      Normalizer.new(resolve_grammar_path(path), mode: @options[:mode]).normalize
    end

    # @rbs (String path) -> Integer
    def process_ir(path)
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
      source = Codegen::Ruby.new(
        automaton, table: @options[:table], embedded: @options.fetch(:embedded, false),
                   line_convert: @options.fetch(:line_convert), debug: @options.fetch(:debug, false),
                   line_convert_all: @options.fetch(:line_convert_all, false),
                   omit_action_call: @options[:omit_actions], superclass: @options[:superclass],
                   executable: @options[:executable], cst_trivia: @options.fetch(:cst_trivia, :attach),
                   error_messages: configured_error_messages(automaton)
      ).generate
      output_path = @options[:output] || default_output_path(input_path, ".rb")
      action_source = action_source_source(automaton) if @options[:action_source]
      write_action_source(output_path, action_source) if action_source
      register_artifact(:parser, output_path, source, mode: (0o755 if @options[:executable]), status: true)
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
      Codegen::RBS.new(
        automaton, superclass: @options[:superclass], omit_action_call: @options[:omit_actions]
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
      Codegen::ActionSource.new(automaton, omit_action_call: @options[:omit_actions]).generate
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
      algorithm = @options[:algorithm] || :lalr
      report_status("building #{algorithm} automaton")
      automaton = LALR::Builder.new(
        grammar, algorithm: algorithm, entry_isolation: @options[:entry_isolation] == true
      ).build
      report_conflicts(automaton, input_path)
      suggest_ielr(automaton, input_path)
      write_report(automaton, input_path) if @options[:verbose] && !@options[:verify_output]
      write_visualizations(automaton) unless @options[:verify_output]
      automaton
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
  # rubocop:enable Metrics/ClassLength
end
