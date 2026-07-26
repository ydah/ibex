# frozen_string_literal: true

module Ibex
  # Bounded grammar ambiguity checking for CI and human inspection.
  module CLIAmbiguity
    # @rbs!
    #   private def print_help: (OptionParser) -> Integer
    #   private def input_path: (Array[String]) -> String
    #   private def positive_counterexample_limit: (Integer, String) -> Integer
    #   private def normalize_grammar_path: (String) -> IR::Grammar

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_check_command(arguments)
      parser = ambiguity_option_parser
      remaining = parser.parse(arguments)
      return print_help(parser) if @options[:help]
      raise Ibex::Error, "(cli):1:1: check command requires --ambiguity" unless @options[:check_ambiguity]

      grammar = normalize_grammar_path(input_path(remaining))
      automaton = LALR::Builder.new(
        grammar, algorithm: @options[:algorithm] || :lalr, entry_isolation: @options[:entry_isolation] == true
      ).build
      check = Codegen::Ambiguity.new(
        automaton,
        max_tokens: @options.fetch(:counterexample_max_tokens),
        max_configurations: @options.fetch(:counterexample_max_configurations)
      )
      output = @options[:check_format] == "json" ? JSON.pretty_generate(check.to_h) : check.render_text
      @stdout.puts(output)
      check.exit_status
    end

    # @rbs () -> OptionParser
    def ambiguity_option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex check --ambiguity [options] grammarfile"
        options.on("--ambiguity", "search parser conflicts for ambiguous sentences") do
          @options[:check_ambiguity] = true
        end
        options.on("--max-tokens=N", Integer, "maximum sentence length (default: 32)") do |value|
          @options[:counterexample_max_tokens] = positive_counterexample_limit(value, "--max-tokens")
        end
        options.on("--max-configurations=N", Integer, "maximum configurations per conflict (default: 50000)") do |value|
          @options[:counterexample_max_configurations] = positive_counterexample_limit(value, "--max-configurations")
        end
        options.on("--format=FORMAT", %w[text json], "text or json (default: text)") do |value|
          @options[:check_format] = value
        end
        options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "parser construction algorithm") do |value|
          @options[:algorithm] = value.to_sym
        end
        options.on("--entry-isolation", "build independent state sets for each start symbol") do
          @options[:entry_isolation] = true
        end
        options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
        options.on("--help", "show help") { @options[:help] = true }
      end
    end
  end
end
