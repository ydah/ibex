# frozen_string_literal: true

module Ibex
  # `%test` command parsing and human-readable result reporting.
  module CLIGrammarTests
    # @rbs!
    #   type grammar_test_settings = {
    #     mode: Symbol,
    #     algorithm: Symbol,
    #     entry_isolation: bool,
    #     timeout: Integer,
    #     ?help: bool
    #   }
    #   private def print_help: (OptionParser) -> Integer
    #   private def resolve_grammar_path: (String) -> Frontend::Resolution
    #   private def handle_grammar_warnings: (IR::Grammar, String) -> void
    #   private def build_automaton: (IR::Grammar, String) -> IR::Automaton

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_grammar_tests_command(arguments)
      settings = {
        mode: :racc, algorithm: :lalr, entry_isolation: false, timeout: GrammarTests::DEFAULT_TIMEOUT
      } #: grammar_test_settings
      options = grammar_test_option_parser(settings)
      remaining = options.parse(arguments)
      return print_help(options) if settings[:help]

      path = single_grammar_test_path(remaining, options)
      @options[:mode] = settings[:mode]
      @options[:algorithm] = settings[:algorithm]
      @options[:entry_isolation] = settings[:entry_isolation]
      resolution = resolve_grammar_path(path)
      grammar = Normalizer.new(resolution, mode: settings[:mode]).normalize
      handle_grammar_warnings(grammar, path)
      automaton = build_automaton(grammar, path)
      results = GrammarTests::Runner.new(automaton, timeout: settings[:timeout]).run
      render_grammar_test_results(results)
    end

    # @rbs (grammar_test_settings settings) -> OptionParser
    def grammar_test_option_parser(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex test [options] grammarfile"
        options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| settings[:mode] = value.to_sym }
        options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "parser construction algorithm") do |value|
          settings[:algorithm] = value.to_sym
        end
        options.on("--entry-isolation", "build independent state sets for each start symbol") do
          settings[:entry_isolation] = true
        end
        options.on("--timeout=SECONDS", Integer, "whole-suite timeout (default: 10)") do |value|
          raise OptionParser::InvalidArgument, "timeout must be positive" unless value.positive?

          settings[:timeout] = value
        end
        options.on("-h", "--help", "show this help") { settings[:help] = true }
      end
    end

    # @rbs (Array[String] remaining, OptionParser options) -> String
    def single_grammar_test_path(remaining, options)
      return remaining.fetch(0) if remaining.one?

      raise OptionParser::MissingArgument, options.banner if remaining.empty?

      raise OptionParser::InvalidArgument, "test accepts exactly one grammarfile"
    end

    # @rbs (Array[GrammarTests::Result] results) -> Integer
    def render_grammar_test_results(results)
      failures = 0
      results.each_with_index do |result, index|
        label = "#{result.expectation} #{result.location[:file]}:#{result.location[:line]}"
        if result.passed?
          @stdout.puts("ok #{index + 1} - #{label}")
        else
          failures += 1
          @stdout.puts("not ok #{index + 1} - #{label} (#{grammar_test_failure(result)})")
        end
      end
      @stdout.puts("#{results.length} tests, #{failures} failures")
      failures.zero? ? 0 : 1
    end

    # @rbs (GrammarTests::Result result) -> String
    def grammar_test_failure(result)
      return "parser #{result.actual}ed the input" unless result.actual == :error

      "#{result.error_class}: #{result.error_message}"
    end
  end
end
