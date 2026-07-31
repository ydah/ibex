# frozen_string_literal: true

require "json"
require "optparse"
require "shellwords"
require_relative "../bounded_subprocess"
require_relative "../fuzz"
require_relative "fuzz_regressions"

module Ibex
  # CLI entry point for bounded grammar-derived differential fuzzing.
  module CLIFuzz
    include CLIFuzzRegressions

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
        against: external&.[](0), against_description: external&.[](1)
      )
      write_fuzz_report(fuzzer.run)
      0
    rescue Fuzz::Mismatch => e
      raise unless fuzzer && path

      begin
        write_minimized_fuzz_mismatch(fuzzer, e, path, external)
      rescue Fuzz::BudgetExceeded => budget
        write_fuzz_budget_report(budget, external, phase: "reduction")
      end
    rescue Fuzz::BudgetExceeded => e
      write_fuzz_budget_report(e, external, phase: "comparison")
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
      add_fuzz_external_options(options)
    end

    # @rbs (OptionParser options) -> void
    def add_fuzz_external_options(options)
      options.on("--against=COMMAND", "compare with an explicit JSON-token subprocess") do |value|
        @options[:fuzz_against] = value
      end
      options.on("--against-runtime=DESCRIPTION", "required target runtime configuration for --against") do |value|
        raise OptionParser::InvalidArgument, "--against-runtime must not be empty" if value.empty?

        @options[:fuzz_against_runtime] = value
      end
      options.on("--against-timeout=SECONDS", Integer, "target timeout per sentence (default 10)") do |value|
        @options[:fuzz_against_timeout] = positive_fuzz_option!("against-timeout", value)
      end
      options.on("--against-max-output=N", Integer, "target stdout/stderr byte budget") do |value|
        @options[:fuzz_against_max_output] = positive_fuzz_option!("against-max-output", value)
      end
      options.on("--max-reduction-trials=N", Integer, "automatic mismatch-reduction trial budget") do |value|
        @options[:fuzz_max_reduction_trials] = positive_fuzz_option!("max-reduction-trials", value)
      end
      options.on("--regression-dir=DIR", "saved minimized regressions (default test/fuzz/regressions)") do |value|
        raise OptionParser::InvalidArgument, "--regression-dir must not be empty" if value.empty?

        @options[:fuzz_regression_dir] = value
      end
      options.on("--[no-]save-regression", "persist minimized mismatches (default enabled)") do |value|
        @options[:fuzz_save_regression] = value
      end
      options.on("--format=FORMAT", %w[json text], "json or text (default json)") do |value|
        @options[:fuzz_format] = value
      end
    end

    # @rbs () -> fuzz_external_target?
    def external_fuzz_target
      command = @options[:fuzz_against]
      runtime = @options[:fuzz_against_runtime]
      if command.nil?
        raise OptionParser::InvalidArgument, "--against-runtime requires --against" if runtime

        return
      end
      unless runtime
        raise OptionParser::InvalidArgument,
              "--against requires --against-runtime so the comparison target is reproducible"
      end

      arguments = Shellwords.split(command)
      raise OptionParser::InvalidArgument, "--against command must not be empty" if arguments.empty?

      timeout = @options.fetch(:fuzz_against_timeout, BoundedSubprocess::DEFAULT_TIMEOUT_SECONDS)
      max_output = @options.fetch(:fuzz_against_max_output, BoundedSubprocess::DEFAULT_MAX_OUTPUT_BYTES)
      subprocess = BoundedSubprocess.new(timeout_seconds: timeout, max_output_bytes: max_output)
      runner = lambda do |tokens|
        external_fuzz_outcome(subprocess, arguments, tokens, timeout, max_output)
      end #: ^(Array[String]) -> Symbol
      description = {
        command: command, target_runtime: runtime,
        timeout_seconds: timeout, max_output_bytes: max_output,
        host_ruby_engine: RUBY_ENGINE, host_ruby_version: RUBY_VERSION,
        host_platform: RUBY_PLATFORM
      } #: fuzz_external_description
      [runner, description]
    end

    # @rbs (BoundedSubprocess subprocess, Array[String] arguments, Array[String] tokens,
    #   Integer timeout, Integer max_output) -> Symbol
    def external_fuzz_outcome(subprocess, arguments, tokens, timeout, max_output)
      result = subprocess.run(arguments, input: JSON.generate(tokens))
      if result.timed_out || result.output_limited
        raise Fuzz::BudgetExceeded.new(
          message: "external target exceeded its #{result.timed_out ? 'timeout' : 'output limit'}",
          bounds: { timeout_seconds: timeout, max_output_bytes: max_output }
        )
      end
      unless result.status.exited? && [0, 1].include?(result.status.exitstatus)
        detail = result.stderr.empty? ? result.stdout : result.stderr
        raise Ibex::Error,
              "(fuzz):1:1: external target did not exit with 0 or 1: #{detail}"
      end

      result.status.success? ? :accepted : :error
    end

    # @rbs (String name, Integer value) -> Integer
    def positive_fuzz_option!(name, value)
      return value if value.positive?

      raise OptionParser::InvalidArgument, "--#{name} must be positive"
    end
  end
end
