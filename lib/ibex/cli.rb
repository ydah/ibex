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
      @options = { emit: "ruby", mode: :racc }
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
  end
end
