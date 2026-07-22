# frozen_string_literal: true

require "optparse"
require_relative "../ibex"
require_relative "cli/counterexample_options"
require_relative "cli/outputs"

module Ibex
  # @rbs!
  #   interface _CLIOutput
  #     def puts: (*untyped) -> untyped
  #     def write: (String) -> untyped
  #   end
  #   type cli_options = {
  #     emit: String,
  #     mode: Symbol,
  #     table: Symbol,
  #     line_convert: bool,
  #     ?line_convert_all: bool,
  #     counterexample_max_tokens: Integer,
  #     counterexample_max_configurations: Integer,
  #     ?from: String,
  #     ?algorithm: Symbol,
  #     ?warnings: Array[Symbol],
  #     ?output: String,
  #     ?embedded: bool,
  #     ?debug: bool,
  #     ?verbose: bool,
  #     ?rbs: String | true,
  #     ?dot: String,
  #     ?html: String,
  #     ?log_file: String,
  #     ?executable: String,
  #     ?frozen: bool,
  #     ?omit_actions: bool,
  #     ?superclass: String,
  #     ?check_only: bool,
  #     ?status: bool,
  #     ?profile: bool,
  #     ?debug_flags: String,
  #     ?version: bool,
  #     ?runtime_version: bool,
  #     ?copyright: bool,
  #     ?help: bool
  #   }

  # Command-line pipeline coordinator.
  # rubocop:disable Metrics/ClassLength -- inline type contracts add lines without adding runtime responsibilities.
  class CLI
    include CLICounterexampleOptions
    include CLIOutputs

    # @rbs @stdout: _CLIOutput
    # @rbs @stderr: _CLIOutput
    # @rbs @options: cli_options

    # @rbs (Array[String] arguments, ?stdout: _CLIOutput, ?stderr: _CLIOutput) -> Integer
    def self.start(arguments, stdout: $stdout, stderr: $stderr)
      new(stdout: stdout, stderr: stderr).run(arguments)
    end

    # @rbs (stdout: _CLIOutput, stderr: _CLIOutput) -> void
    def initialize(stdout:, stderr:)
      @stdout = stdout
      @stderr = stderr
      @options = { emit: "ruby", mode: :racc, table: :compact, line_convert: true }
                 .merge(CLICounterexampleOptions::DEFAULTS)
    end

    # @rbs (Array[String] arguments) -> Integer
    def run(arguments)
      parser = option_parser
      remaining = parser.parse(arguments)
      information = informational_result(parser)
      return information unless information.nil?

      process_grammar(input_path(remaining))
    rescue OptionParser::ParseError, Ibex::Error, Errno::ENOENT => e
      @stderr.puts(e.message)
      1
    end

    private

    # @rbs () -> OptionParser
    def option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex [options] grammarfile"
        add_pipeline_options(options)
        add_output_options(options)
        add_compatibility_options(options)
        add_information_options(options)
      end
    end

    # @rbs (OptionParser options) -> void
    def add_pipeline_options(options)
      options.on("--emit=FORMAT", "ast, grammar-ir, automaton-ir, or ruby") { |value| @options[:emit] = value }
      options.on("--from=FORMAT", %w[grammar-ir automaton-ir], "resume from IR JSON") do |value|
        @options[:from] = value
      end
      options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
      options.on("--table=FORMAT", %w[plain compact], "parser table format") do |value|
        @options[:table] = value.to_sym
      end
      options.on("--algorithm=NAME", %w[slr lalr lr1], "parser construction algorithm") do |value|
        @options[:algorithm] = value.to_sym
      end
      options.on("--warnings=CATEGORIES", "all, error, all,error, or none") do |value|
        @options[:warnings] = warning_categories(value)
      end
    end

    # @rbs (OptionParser options) -> void
    def add_output_options(options)
      options.on("-o", "--output-file=FILE", "generated parser path") { |value| @options[:output] = value }
      options.on("-E", "--embedded", "embed the Pure Ruby runtime") { @options[:embedded] = true }
      options.on("-t", "--debug", "generate a debug-capable parser") { @options[:debug] = true }
      options.on("-g", "obsolete alias for --debug") { @options[:debug] = true }
      options.on("-v", "--verbose", "write an automaton report") { @options[:verbose] = true }
      add_counterexample_options(options)
      options.on("--rbs[=FILE]", "write an RBS signature (defaults beside parser)") do |value|
        @options[:rbs] = value || true
      end
      options.on("--dot=FILE", "write Graphviz DOT") { |value| @options[:dot] = value }
      options.on("--html=FILE", "write a self-contained HTML report") { |value| @options[:html] = value }
      options.on("-O", "--log-file=FILE", "automaton report path") do |value|
        @options[:verbose] = true
        @options[:log_file] = value
      end
      options.on("-e", "--executable [RUBY]", "add a shebang") do |value|
        @options[:executable] = value || "/usr/bin/env ruby"
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

    # @rbs (String path) -> Integer
    def process_grammar(path)
      return process_ir(path) if @options[:from]

      report_status("reading #{path}")
      ast = Frontend::Parser.new(File.read(path), file: path, mode: @options[:mode]).parse
      return emit_ast(ast) if @options[:emit] == "ast"

      grammar = Normalizer.new(ast, mode: @options[:mode]).normalize
      dispatch_grammar(grammar, path)
    end

    # @rbs (String path) -> Integer
    def process_ir(path)
      report_status("reading #{path}")
      value = IR::Serialize.load(File.read(path))
      expected = @options[:from] == "grammar-ir" ? IR::Grammar : IR::Automaton
      raise Ibex::Error, "#{path}:1:1: expected #{@options[:from]} input" unless value.is_a?(expected)

      return dispatch_grammar(value, path) if value.is_a?(IR::Grammar)

      dispatch_automaton(value, path)
    end

    # @rbs (IR::Grammar grammar, String path) -> Integer
    def dispatch_grammar(grammar, path)
      handle_grammar_warnings(grammar, path)
      return 0 if @options[:check_only]
      return emit_grammar(grammar) if @options[:emit] == "grammar-ir"
      return emit_automaton(grammar, path) if @options[:emit] == "automaton-ir"
      return emit_ruby(grammar, path) if @options[:emit] == "ruby"

      raise Ibex::Error, "(cli):1:1: emit format #{@options[:emit].inspect} is not available yet"
    end

    # @rbs (IR::Automaton automaton, String path) -> Integer
    def dispatch_automaton(automaton, path)
      handle_grammar_warnings(automaton.grammar, path)
      return 0 if @options[:check_only]
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
      @stdout.write(IR::Serialize.dump(grammar))
      0
    end

    # @rbs (IR::Grammar grammar, String input_path) -> Integer
    def emit_automaton(grammar, input_path)
      @stdout.write(IR::Serialize.dump(build_automaton(grammar, input_path)))
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
                   executable: @options[:executable]
      ).generate
      output_path = @options[:output] || default_output_path(input_path, ".rb")
      File.write(output_path, source)
      File.chmod(0o755, output_path) if @options[:executable]
      report_status("wrote #{output_path}")
      write_rbs(automaton, output_path) if @options[:rbs]
      0
    end

    # @rbs (IR::Automaton automaton, String output_path) -> void
    def write_rbs(automaton, output_path)
      configured_path = @options[:rbs]
      path = configured_path == true ? default_output_path(output_path, ".rbs") : configured_path
      raise ArgumentError, "RBS output path is required" unless path.is_a?(String)

      source = Codegen::RBS.new(automaton, superclass: @options[:superclass]).generate
      File.write(path, source)
      report_status("wrote #{path}")
    end

    # @rbs (IR::Automaton automaton, String input_path) -> Integer
    def emit_loaded_automaton(automaton, input_path)
      prepare_loaded_automaton(automaton, input_path)
      @stdout.write(IR::Serialize.dump(automaton))
      0
    end

    # @rbs (IR::Grammar grammar, String input_path) -> IR::Automaton
    def build_automaton(grammar, input_path)
      report_status("building LALR automaton")
      automaton = LALR::Builder.new(grammar, algorithm: @options[:algorithm] || :lalr).build
      report_conflicts(automaton, input_path)
      write_report(automaton, input_path) if @options[:verbose]
      write_visualizations(automaton)
      automaton
    end

    # @rbs (IR::Automaton automaton, String input_path) -> void
    def prepare_loaded_automaton(automaton, input_path)
      report_conflicts(automaton, input_path)
      write_report(automaton, input_path) if @options[:verbose]
      write_visualizations(automaton)
    end

    # @rbs (IR::Automaton automaton) -> void
    def write_visualizations(automaton)
      dot_path = @options[:dot]
      html_path = @options[:html]
      File.write(dot_path, Codegen::Dot.render(automaton)) if dot_path
      File.write(html_path, Codegen::HTML.render(automaton)) if html_path
    end
  end
  # rubocop:enable Metrics/ClassLength
end
