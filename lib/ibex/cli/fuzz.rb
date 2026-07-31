# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "shellwords"
require_relative "../fuzz"

module Ibex
  # CLI entry point for bounded grammar-derived differential fuzzing.
  module CLIFuzz
    # @rbs!
    #   private def print_help: (OptionParser) -> Integer
    #   private def input_path: (Array[String]) -> String
    #   private def normalize_grammar_path: (String) -> IR::Grammar
    #   private def handle_grammar_warnings: (IR::Grammar, String) -> void
    #   private def warning_categories: (String) -> Array[Symbol]

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_fuzz_command(arguments)
      parser = fuzz_option_parser
      remaining = parser.parse(arguments)
      return print_help(parser) if @options[:help]

      path = input_path(remaining)
      grammar = normalize_grammar_path(path)
      handle_grammar_warnings(grammar, path)
      external = external_fuzz_target
      fuzzer = Fuzz.new(
        grammar,
        seed: @options.fetch(:fuzz_seed, 0), count: @options.fetch(:fuzz_count, 100),
        max_tokens: @options.fetch(:fuzz_max_tokens, 32), max_depth: @options.fetch(:fuzz_max_depth, 16),
        max_expansions: @options.fetch(:fuzz_max_expansions, Samples::DEFAULT_MAX_EXPANSIONS),
        max_actions: @options.fetch(:fuzz_max_actions, Fuzz::DEFAULT_MAX_ACTIONS),
        max_stack: @options.fetch(:fuzz_max_stack, Fuzz::DEFAULT_MAX_STACK),
        coverage_guided: @options.fetch(:fuzz_coverage_guided, false),
        path_length: @options.fetch(:fuzz_path_length, 2),
        against: external&.fetch(0), against_description: external&.fetch(1)
      )
      @stdout.puts JSON.pretty_generate(fuzzer.run)
      0
    rescue Fuzz::Mismatch => e
      @stdout.puts JSON.pretty_generate(
        { ibex_report: "fuzz", schema_version: 1, result: "difference", mismatch: e.details }
      )
      1
    rescue Fuzz::BudgetExceeded => e
      @stdout.puts JSON.pretty_generate(
        { ibex_report: "fuzz", schema_version: 1, result: "budget_exhausted", budget: e.details }
      )
      2
    end

    # @rbs () -> OptionParser
    def fuzz_option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex fuzz [options] grammarfile"
        add_fuzz_generation_options(options)
        add_fuzz_execution_options(options)
        options.on("--mode=MODE", %w[default extended], "grammar mode") { |value| @options[:mode] = value.to_sym }
        options.on("--warnings=CATEGORIES", "all, error, all,error, or none") do |value|
          @options[:warnings] = warning_categories(value)
        end
        options.on("--help", "show help") { @options[:help] = true }
      end
    end

    # @rbs (OptionParser options) -> void
    def add_fuzz_generation_options(options)
      options.on("--count=N", Integer, "generated sentences (default 100)") do |value|
        @options[:fuzz_count] = positive_fuzz_option!("count", value)
      end
      options.on("--seed=N", Integer, "deterministic seed (default 0)") { |value| @options[:fuzz_seed] = value }
      options.on("--max-tokens=N", Integer, "maximum generated tokens") do |value|
        @options[:fuzz_max_tokens] = positive_fuzz_option!("max-tokens", value)
      end
      options.on("--max-depth=N", Integer, "maximum random expansion depth") do |value|
        @options[:fuzz_max_depth] = positive_fuzz_option!("max-depth", value)
      end
      options.on("--max-expansions=N", Integer, "total derivation work budget") do |value|
        @options[:fuzz_max_expansions] = positive_fuzz_option!("max-expansions", value)
      end
    end

    # @rbs (OptionParser options) -> void
    def add_fuzz_execution_options(options)
      options.on("--max-actions=N", Integer, "actions per simulated sentence") do |value|
        @options[:fuzz_max_actions] = positive_fuzz_option!("max-actions", value)
      end
      options.on("--max-stack=N", Integer, "simulated parser stack depth") do |value|
        @options[:fuzz_max_stack] = positive_fuzz_option!("max-stack", value)
      end
      options.on("--coverage-guided", "prefer uncovered production paths") do
        @options[:fuzz_coverage_guided] = true
      end
      options.on("--path-length=N", Integer, "coverage path length: 1 or 2") do |value|
        raise OptionParser::InvalidArgument, "--path-length must be 1 or 2" unless [1, 2].include?(value)

        @options[:fuzz_path_length] = value
      end
      options.on("--against=COMMAND", "compare with an explicit JSON-token subprocess") do |value|
        @options[:fuzz_against] = value
      end
    end

    # @rbs () -> [(^(Array[String]) -> Symbol), Hash[Symbol, untyped]]?
    def external_fuzz_target
      command = @options[:fuzz_against]
      return unless command

      arguments = Shellwords.split(command)
      raise OptionParser::InvalidArgument, "--against command must not be empty" if arguments.empty?

      runner = lambda do |tokens|
        output, errors, status = Open3.capture3(*arguments, stdin_data: JSON.generate(tokens))
        unless [0, 1].include?(status.exitstatus)
          raise Ibex::Error,
                "(fuzz):1:1: external target exited #{status.exitstatus}: #{errors.empty? ? output : errors}"
        end
        status.success? ? :accepted : :error
      end
      description = {
        command: command, host_ruby_engine: RUBY_ENGINE, host_ruby_version: RUBY_VERSION,
        host_platform: RUBY_PLATFORM
      }
      [runner, description]
    end

    # @rbs (String name, Integer value) -> Integer
    def positive_fuzz_option!(name, value)
      return value if value.positive?

      raise OptionParser::InvalidArgument, "--#{name} must be positive"
    end
  end
end
