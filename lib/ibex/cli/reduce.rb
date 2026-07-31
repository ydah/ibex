# frozen_string_literal: true

require "json"
require "optparse"
require "shellwords"
require_relative "../bounded_subprocess"
require_relative "../delta_reducer"
require_relative "reduce_reporting"

module Ibex
  # @rbs!
  #   type reduction_bounds = {
  #     max_trials: Integer,
  #     timeout_seconds: Integer,
  #     max_output_bytes: Integer,
  #     max_input_bytes: Integer
  #   }
  #   type reduction_budget_details = {
  #     kind: String,
  #     message: String,
  #     trials: Integer
  #   }
  #   type reduction_success_document = {
  #     ibex_report: String,
  #     schema_version: Integer,
  #     result: String,
  #     mode: Symbol,
  #     original_size: Integer,
  #     minimized_size: Integer,
  #     trials: Integer,
  #     complete: bool,
  #     minimized: Array[String | Integer],
  #     bounded: bool,
  #     bounds: reduction_bounds
  #   }
  #   type reduction_budget_document = {
  #     ibex_report: String,
  #     schema_version: Integer,
  #     result: String,
  #     mode: Symbol,
  #     bounded: bool,
  #     bounds: reduction_bounds,
  #     budget: reduction_budget_details
  #   }

  # CLI entry point for generic bounded delta debugging.
  module CLIReduce
    include CLIReduceReporting

    DEFAULT_MAX_INPUT_BYTES = 10 * 1024 * 1024 #: Integer

    class ReductionBudgetExceeded < Ibex::Error
      attr_reader :details #: reduction_budget_details

      # @rbs (reduction_budget_details details) -> void
      def initialize(details)
        @details = details
        super("(reduce):1:1: configured resource budget was exhausted")
      end
    end

    # @rbs @reduction_mode: Symbol
    # @rbs @reduction_bounds: reduction_bounds
    # @rbs @reduction_trials: Integer
    # @rbs @reduction_subprocess: BoundedSubprocess

    # @rbs!
    #   private def print_help: (OptionParser) -> Integer
    #   private def input_path: (Array[String]) -> String

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_reduce_command(arguments)
      parser = reduce_option_parser
      remaining = parser.parse(arguments)
      return print_help(parser) if @options[:help]

      path = input_path(remaining)
      configured_command = @options[:reduce_command]
      raise OptionParser::MissingArgument, "--command" unless configured_command

      command = Shellwords.split(configured_command)
      raise OptionParser::InvalidArgument, "--command must not be empty" if command.empty?

      prepare_reduction_run
      source = bounded_reduction_source(path)
      items = reduction_items(source, @reduction_mode)
      reducer = DeltaReducer.new(max_trials: @reduction_bounds.fetch(:max_trials))
      result = reducer.minimize(items) { |candidate| reduction_failure?(command, candidate, @reduction_mode) }
      write_reduction_success(reduction_success_report(result))
      result.complete ? 0 : 2
    rescue ReductionBudgetExceeded => e
      write_reduction_budget(reduction_budget_report(e.details))
      2
    end

    # @rbs () -> OptionParser
    def reduce_option_parser
      OptionParser.new do |options|
        options.banner = "Usage: ibex reduce --command=COMMAND [options] input"
        options.on("--command=COMMAND", "nonzero exit means the failure persists") do |value|
          @options[:reduce_command] = value
        end
        options.on("--mode=MODE", %w[tokens lines bytes], "tokens, lines, or bytes") do |value|
          @options[:reduce_mode] = value.to_sym
        end
        options.on("--max-trials=N", Integer, "subprocess trial budget (default 1000)") do |value|
          @options[:reduce_max_trials] = positive_reduce_option!("max-trials", value)
        end
        options.on("--timeout=SECONDS", Integer, "checker timeout per trial (default 10)") do |value|
          @options[:reduce_timeout] = positive_reduce_option!("timeout", value)
        end
        options.on("--max-output-bytes=N", Integer, "checker stdout/stderr byte budget") do |value|
          @options[:reduce_max_output_bytes] = positive_reduce_option!("max-output-bytes", value)
        end
        options.on("--max-input-bytes=N", Integer, "input byte budget (default 10485760)") do |value|
          @options[:reduce_max_input_bytes] = positive_reduce_option!("max-input-bytes", value)
        end
        options.on("--format=FORMAT", %w[json text], "json or text (default json)") do |value|
          @options[:reduce_format] = value
        end
        options.on("--help", "show help") { @options[:help] = true }
      end
    end

    # @rbs () -> void
    def prepare_reduction_run
      @reduction_mode = @options.fetch(:reduce_mode, :tokens)
      @reduction_bounds = {
        max_trials: @options.fetch(:reduce_max_trials, 1_000),
        timeout_seconds: @options.fetch(:reduce_timeout, BoundedSubprocess::DEFAULT_TIMEOUT_SECONDS),
        max_output_bytes: @options.fetch(
          :reduce_max_output_bytes, BoundedSubprocess::DEFAULT_MAX_OUTPUT_BYTES
        ),
        max_input_bytes: @options.fetch(:reduce_max_input_bytes, DEFAULT_MAX_INPUT_BYTES)
      }
      @reduction_trials = 0
      @reduction_subprocess = BoundedSubprocess.new(
        timeout_seconds: @reduction_bounds.fetch(:timeout_seconds),
        max_output_bytes: @reduction_bounds.fetch(:max_output_bytes)
      )
    end

    # @rbs (String path) -> String
    def bounded_reduction_source(path)
      maximum = @reduction_bounds.fetch(:max_input_bytes)
      source = File.binread(path, maximum + 1)
      return source if source.bytesize <= maximum

      raise ReductionBudgetExceeded.new(
        kind: "input_bytes", message: "input exceeds #{maximum} bytes", trials: 0
      )
    end

    # @rbs (String source, Symbol mode) -> Array[String | Integer]
    def reduction_items(source, mode)
      case mode
      when :tokens
        parsed = JSON.parse(source)
        raise Ibex::Error, "(reduce):1:1: token input must be a JSON array" unless parsed.is_a?(Array)
        raise Ibex::Error, "(reduce):1:1: every token must be a string" unless parsed.all?(String)

        parsed
      when :lines then source.lines
      when :bytes then source.bytes
      else raise Ibex::Error, "(reduce):1:1: unknown reduction mode #{mode.inspect}"
      end
    rescue JSON::ParserError => e
      raise Ibex::Error, "(reduce):1:1: invalid token JSON: #{e.message}"
    end

    # @rbs (Array[String] command, Array[String | Integer] candidate, Symbol mode) -> bool
    def reduction_failure?(command, candidate, mode)
      input = case mode
              when :tokens then JSON.generate(candidate)
              when :lines then candidate.join
              when :bytes then candidate.pack("C*")
              else raise Ibex::Error, "(reduce):1:1: unknown reduction mode #{mode.inspect}"
              end
      @reduction_trials += 1
      result = @reduction_subprocess.run(command, input: input)
      if result.timed_out || result.output_limited
        kind = result.timed_out ? "subprocess_timeout" : "subprocess_output"
        message = result.timed_out ? "checker timed out" : "checker exceeded its output byte budget"
        raise ReductionBudgetExceeded.new(kind: kind, message: message, trials: @reduction_trials)
      end
      unless result.status.exited?
        raise Ibex::Error, "(reduce):1:1: checker terminated by signal #{result.status.termsig}"
      end

      !result.status.success?
    end

    # @rbs (String name, Integer value) -> Integer
    def positive_reduce_option!(name, value)
      return value if value.positive?

      raise OptionParser::InvalidArgument, "--#{name} must be positive"
    end
  end
end
