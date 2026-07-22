# frozen_string_literal: true

require "optparse"
require_relative "../ibex"

module Ibex
  # Command-line pipeline coordinator.
  class CLI
    def self.start(arguments, stdout: $stdout, stderr: $stderr)
      new(stdout: stdout, stderr: stderr).run(arguments)
    end

    def initialize(stdout:, stderr:)
      @stdout = stdout
      @stderr = stderr
      @options = { emit: "ruby", mode: :racc, table: :compact, line_convert: true }
    end

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

    def option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex [options] grammarfile"
        add_pipeline_options(options)
        add_output_options(options)
        add_compatibility_options(options)
        add_information_options(options)
      end
    end

    def add_pipeline_options(options)
      options.on("--emit=FORMAT", "ast, grammar-ir, automaton-ir, or ruby") { |value| @options[:emit] = value }
      options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
      options.on("--table=FORMAT", %w[plain compact], "parser table format") do |value|
        @options[:table] = value.to_sym
      end
    end

    def add_output_options(options)
      options.on("-o", "--output-file=FILE", "generated parser path") { |value| @options[:output] = value }
      options.on("-E", "--embedded", "embed the Pure Ruby runtime") { @options[:embedded] = true }
      options.on("-t", "--debug", "generate a debug-capable parser") { @options[:debug] = true }
      options.on("-g", "obsolete alias for --debug") { @options[:debug] = true }
      options.on("-v", "--verbose", "write an automaton report") { @options[:verbose] = true }
      options.on("-O", "--log-file=FILE", "automaton report path") do |value|
        @options[:verbose] = true
        @options[:log_file] = value
      end
      options.on("-e", "--executable [RUBY]", "add a shebang") do |value|
        @options[:executable] = value || "/usr/bin/env ruby"
      end
    end

    def add_compatibility_options(options)
      options.on("-F", "--frozen", "emit frozen string literals") { @options[:frozen] = true }
      options.on("--line-convert-all", "convert all source lines") { @options[:line_convert] = true }
      options.on("-l", "--no-line-convert", "use generated-file action lines") { @options[:line_convert] = false }
      options.on("-a", "--no-omit-actions", "generate implicit action methods") { @options[:omit_actions] = false }
      options.on("--superclass=CLASS", "override parser superclass") { |value| @options[:superclass] = value }
      options.on("-C", "--check-only", "check grammar and exit") { @options[:check_only] = true }
      options.on("-S", "--output-status", "show pipeline status") { @options[:status] = true }
      options.on("-P", "accept the compatibility profiling flag") { @options[:profile] = true }
      options.on("-D FLAGS", "accept internal compatibility flags") { |value| @options[:debug_flags] = value }
    end

    def add_information_options(options)
      options.on("--version", "show version") { @options[:version] = true }
      options.on("--runtime-version", "show runtime version") { @options[:runtime_version] = true }
      options.on("--copyright", "show copyright") { @options[:copyright] = true }
      options.on("--help", "show help") { @options[:help] = true }
    end

    def informational_result(parser)
      return print_version if @options[:version] || @options[:runtime_version]
      return print_copyright if @options[:copyright]
      return print_help(parser) if @options[:help]

      nil
    end

    def input_path(remaining)
      path = remaining.first || raise(Ibex::Error, "(cli):1:1: grammar file is required")
      raise Ibex::Error, "(cli):1:1: only one grammar file may be specified" if remaining.length > 1

      path
    end

    def process_grammar(path)
      report_status("reading #{path}")
      ast = Frontend::Parser.new(File.read(path), file: path, mode: @options[:mode]).parse
      return emit_ast(ast) if @options[:emit] == "ast"

      grammar = Normalizer.new(ast, mode: @options[:mode]).normalize
      dispatch_grammar(grammar, path)
    end

    def dispatch_grammar(grammar, path)
      return 0 if @options[:check_only]
      return emit_grammar(grammar) if @options[:emit] == "grammar-ir"
      return emit_automaton(grammar, path) if @options[:emit] == "automaton-ir"
      return emit_ruby(grammar, path) if @options[:emit] == "ruby"

      raise Ibex::Error, "(cli):1:1: emit format #{@options[:emit].inspect} is not available yet"
    end

    def print_version
      @stdout.puts("ibex #{VERSION}")
      0
    end

    def print_help(parser)
      @stdout.puts(parser)
      0
    end

    def print_copyright
      @stdout.puts("Ibex #{VERSION} Copyright (c) 2026 Yudai Takada")
      0
    end

    def emit_ast(ast)
      @stdout.puts(JSON.pretty_generate(ast.to_h))
      0
    end

    def emit_grammar(grammar)
      @stdout.write(IR::Serialize.dump(grammar))
      0
    end

    def emit_automaton(grammar, input_path)
      @stdout.write(IR::Serialize.dump(build_automaton(grammar, input_path)))
      0
    end

    def emit_ruby(grammar, input_path)
      automaton = build_automaton(grammar, input_path)
      source = Codegen::Ruby.new(
        automaton, table: @options[:table], embedded: @options[:embedded],
                   line_convert: @options[:line_convert], debug: @options[:debug],
                   omit_action_call: @options[:omit_actions], superclass: @options[:superclass],
                   executable: @options[:executable]
      ).generate
      output_path = @options[:output] || default_output_path(input_path, ".rb")
      File.write(output_path, source)
      File.chmod(0o755, output_path) if @options[:executable]
      report_status("wrote #{output_path}")
      0
    end

    def build_automaton(grammar, input_path)
      report_status("building LALR automaton")
      automaton = LALR::Builder.new(grammar).build
      report_conflicts(automaton, input_path)
      write_report(automaton, input_path) if @options[:verbose]
      automaton
    end

    def report_conflicts(automaton, input_path)
      summary = automaton.conflict_summary
      unless summary[:expectation_met]
        @stderr.puts("#{input_path}:1:1: #{summary[:sr]} shift/reduce conflicts; expected #{summary[:expected_sr]}")
      end
      @stderr.puts("#{input_path}:1:1: #{summary[:rr]} reduce/reduce conflicts") if summary[:rr].positive?
    end

    def write_report(automaton, input_path)
      path = @options[:log_file] || default_output_path(input_path, ".output")
      File.write(path, Codegen::Report.render(automaton))
      report_status("wrote #{path}")
    end

    def default_output_path(input_path, extension)
      replaced = input_path.sub(/\.[^.]+\z/, extension)
      replaced == input_path ? "#{input_path}#{extension}" : replaced
    end

    def report_status(message)
      @stderr.puts("ibex: #{message}") if @options[:status]
    end
  end
end
