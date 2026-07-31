# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "shellwords"
require_relative "../delta_reducer"

module Ibex
  # CLI entry point for generic bounded delta debugging.
  module CLIReduce
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
      command = Shellwords.split(@options.fetch(:reduce_command))
      raise OptionParser::InvalidArgument, "--command must not be empty" if command.empty?

      mode = @options.fetch(:reduce_mode, :tokens)
      items = reduction_items(File.binread(path), mode)
      reducer = DeltaReducer.new(max_trials: @options.fetch(:reduce_max_trials, 1_000))
      result = reducer.minimize(items) { |candidate| reduction_failure?(command, candidate, mode) }
      @stdout.puts JSON.pretty_generate(
        ibex_report: "reduce", schema_version: 1, mode: mode,
        original_size: result.original_size, minimized_size: result.items.length,
        trials: result.trials, complete: result.complete, minimized: result.items,
        bounded: true
      )
      result.complete ? 0 : 2
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
          raise OptionParser::InvalidArgument, "--max-trials must be positive" unless value.positive?

          @options[:reduce_max_trials] = value
        end
        options.on("--help", "show help") { @options[:help] = true }
      end
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
      _output, _errors, status = Open3.capture3(*command, stdin_data: input)
      !status.success?
    end
  end
end
