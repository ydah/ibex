# frozen_string_literal: true

module Ibex
  # CLI entry point for bounded grammar sentence generation.
  module CLISamples
    # @rbs!
    #   private def print_help: (OptionParser) -> Integer
    #   private def input_path: (Array[String]) -> String
    #   private def handle_grammar_warnings: (IR::Grammar, String) -> void
    #   private def warning_categories: (String) -> Array[Symbol]

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_samples_command(arguments)
      parser = samples_option_parser
      remaining = parser.parse(arguments)
      return print_help(parser) if @options[:help]

      path = input_path(remaining)
      grammar = grammar_for_samples(path)
      handle_grammar_warnings(grammar, path)
      generator = Samples.new(
        grammar,
        seed: @options.fetch(:sample_seed, 0),
        max_tokens: @options.fetch(:sample_max_tokens, 32),
        max_depth: @options.fetch(:sample_max_depth, 16),
        max_expansions: @options.fetch(:sample_max_expansions, Samples::DEFAULT_MAX_EXPANSIONS)
      )
      generator.generate(count: @options.fetch(:sample_count, 5)).each do |sample|
        @stdout.puts(JSON.generate(sample))
      end
      0
    end

    # @rbs () -> OptionParser
    def samples_option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex samples [options] grammarfile"
        options.on("--count=N", Integer, "number of samples (default 5)") do |value|
          @options[:sample_count] = positive_sample_option!("count", value)
        end
        options.on("--seed=N", Integer, "deterministic random seed (default 0)") do |value|
          @options[:sample_seed] = value
        end
        options.on("--max-tokens=N", Integer, "maximum tokens per sample (default 32)") do |value|
          @options[:sample_max_tokens] = positive_sample_option!("max-tokens", value)
        end
        options.on("--max-depth=N", Integer, "random expansion depth (default 16)") do |value|
          @options[:sample_max_depth] = positive_sample_option!("max-depth", value)
        end
        options.on("--max-expansions=N", Integer, "total expansion steps (default 100000)") do |value|
          @options[:sample_max_expansions] = positive_sample_option!("max-expansions", value)
        end
        options.on("--from=FORMAT", %w[grammar-ir automaton-ir], "read versioned IR JSON") do |value|
          @options[:from] = value
        end
        options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
        options.on("--warnings=CATEGORIES", "all, error, all,error, or none") do |value|
          @options[:warnings] = warning_categories(value)
        end
        options.on("--help", "show help") { @options[:help] = true }
      end
    end

    # @rbs (String path) -> IR::Grammar
    def grammar_for_samples(path)
      unless @options[:from]
        source = File.read(path)
        ast = Frontend::Parser.new(source, file: path, mode: @options[:mode]).parse
        return Normalizer.new(ast, mode: @options[:mode]).normalize
      end

      value = IR::Validator.validate(File.read(path))
      expected = @options[:from] == "grammar-ir" ? IR::Grammar : IR::Automaton
      raise Ibex::Error, "#{path}:1:1: expected #{@options[:from]} input" unless value.is_a?(expected)

      value.is_a?(IR::Grammar) ? value : value.grammar
    end

    # @rbs (String name, Integer value) -> Integer
    def positive_sample_option!(name, value)
      return value if value.positive?

      raise OptionParser::InvalidArgument, "--#{name} must be positive"
    end
  end
end
