# frozen_string_literal: true

module Ibex
  # Dedicated command-line view for selected parser conflicts.
  module CLIExplain
    # @rbs!
    #   private def print_help: (OptionParser) -> Integer
    #   private def input_path: (Array[String]) -> String
    #   private def positive_counterexample_limit: (Integer, String) -> Integer
    #   private def normalize_grammar_path: (String) -> IR::Grammar

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_explain_command(arguments)
      parser = explain_option_parser
      remaining = parser.parse(arguments)
      return print_help(parser) if @options[:help]

      path = input_path(remaining)
      grammar = normalize_grammar_path(path)
      automaton = LALR::Builder.new(grammar, algorithm: @options[:algorithm] || :lalr).build
      explanation = Codegen::Explain.new(
        automaton, state: @options[:explain_state], token: @options[:explain_token],
                   max_tokens: @options.fetch(:counterexample_max_tokens),
                   max_configurations: @options.fetch(:counterexample_max_configurations)
      )
      output = @options[:explain_format] == "json" ? JSON.pretty_generate(explanation.to_h) : explanation.render_text
      @stdout.puts(output)
      0
    end

    # @rbs () -> OptionParser
    def explain_option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex explain [options] grammarfile"
        options.on("--state=N", Integer, "select one automaton state") { |value| @options[:explain_state] = value }
        options.on("--token=NAME", "select a grammar token name or exact display name") do |value|
          @options[:explain_token] = value
        end
        options.on("--format=FORMAT", %w[text json], "text or json (default: text)") do |value|
          @options[:explain_format] = value
        end
        options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "parser construction algorithm") do |value|
          @options[:algorithm] = value.to_sym
        end
        options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
        add_explain_search_options(options)
        options.on("--help", "show help") { @options[:help] = true }
      end
    end

    # @rbs (OptionParser options) -> void
    def add_explain_search_options(options)
      options.on("--counterexample-max-tokens=N", Integer, "maximum counterexample search token budget") do |value|
        @options[:counterexample_max_tokens] = positive_counterexample_limit(value, "--counterexample-max-tokens")
      end
      options.on(
        "--counterexample-max-configurations=N", Integer, "maximum counterexample search configuration budget"
      ) do |value|
        @options[:counterexample_max_configurations] = positive_counterexample_limit(
          value, "--counterexample-max-configurations"
        )
      end
    end
  end
end
