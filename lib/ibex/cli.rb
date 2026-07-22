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
      return print_version if @options[:version]
      return print_help(parser) if @options[:help]

      path = remaining.first || raise(Ibex::Error, "(cli):1:1: grammar file is required")
      ast = Frontend::Parser.new(File.read(path), file: path, mode: @options[:mode]).parse
      grammar = Normalizer.new(ast, mode: @options[:mode]).normalize
      return emit_grammar(grammar) if @options[:emit] == "grammar-ir"
      return emit_automaton(grammar) if @options[:emit] == "automaton-ir"
      return emit_ruby(grammar, path) if @options[:emit] == "ruby"

      raise Ibex::Error, "(cli):1:1: emit format #{@options[:emit].inspect} is not available yet"
    rescue OptionParser::ParseError, Ibex::Error, Errno::ENOENT => e
      @stderr.puts(e.message)
      1
    end

    private

    def option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex [options] grammarfile"
        options.on("--emit=FORMAT", "ast, grammar-ir, automaton-ir, or ruby") { |value| @options[:emit] = value }
        options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
        options.on("--table=FORMAT", %w[plain compact], "parser table format") do |value|
          @options[:table] = value.to_sym
        end
        options.on("-o", "--output-file=FILE", "generated parser path") { |value| @options[:output] = value }
        options.on("-E", "--embedded", "embed the Pure Ruby runtime") { @options[:embedded] = true }
        options.on("-l", "--no-line-convert", "use generated-file action lines") { @options[:line_convert] = false }
        options.on("-a", "--no-omit-actions", "generate implicit action methods") { @options[:omit_actions] = false }
        options.on("--version", "show version") { @options[:version] = true }
        options.on("--help", "show help") { @options[:help] = true }
      end
    end

    def print_version
      @stdout.puts("ibex #{VERSION}")
      0
    end

    def print_help(parser)
      @stdout.puts(parser)
      0
    end

    def emit_grammar(grammar)
      @stdout.write(IR::Serialize.dump(grammar))
      0
    end

    def emit_automaton(grammar)
      @stdout.write(IR::Serialize.dump(LALR::Builder.new(grammar).build))
      0
    end

    def emit_ruby(grammar, input_path)
      automaton = LALR::Builder.new(grammar).build
      source = Codegen::Ruby.new(
        automaton, table: @options[:table], embedded: @options[:embedded],
                   line_convert: @options[:line_convert], omit_action_call: @options[:omit_actions]
      ).generate
      output_path = @options[:output] || input_path.sub(/\.[^.]+\z/, ".rb")
      File.write(output_path, source)
      0
    end
  end
end
