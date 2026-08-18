# frozen_string_literal: true
# rbs_inline: enabled

require "tempfile"
require_relative "../coverage"

module Ibex
  # CLI collection, merge, and threshold checks for runtime coverage.
  module CLICoverage
    # @rbs!
    #   private def same_file_target?: (String left, String right) -> bool
    #
    #   type coverage_output_options = {
    #     paths: Array[String],
    #     ?output: String
    #   }
    #   type coverage_check_options = {
    #     paths: Array[String],
    #     min_states: Float,
    #     min_productions: Float
    #   }

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_coverage_command(arguments)
      if arguments == ["--help"]
        @stdout.puts("Usage: ibex coverage collect|merge|check [options] FILE...")
        return 0
      end

      operation = arguments.shift
      case operation
      when "collect" then run_coverage_collect(arguments)
      when "merge" then run_coverage_merge(arguments)
      when "check" then run_coverage_check(arguments)
      else
        raise Ibex::Error, "(cli):1:1: coverage requires collect, merge, or check"
      end
    end

    # @rbs (Array[String] arguments) -> Integer
    def run_coverage_collect(arguments)
      settings = coverage_output_options(arguments, "collect", "INPUT")
      input = single_coverage_path(settings.fetch(:paths), "coverage collect")
      reject_coverage_output_collision([input], settings[:output])
      report = Coverage::Collector.collect_file(input)
      write_coverage_report(report, settings[:output])
      0
    end

    # @rbs (Array[String] arguments) -> Integer
    def run_coverage_merge(arguments)
      settings = coverage_output_options(arguments, "merge", "INPUT...")
      inputs = settings.fetch(:paths)
      raise Ibex::Error, "(cli):1:1: coverage merge requires at least one input" if inputs.empty?

      reject_coverage_output_collision(inputs, settings[:output])
      reports = inputs.map { |path| Coverage::Report.load_file(path) }
      report = Coverage::Report.merge(reports)
      write_coverage_report(report, settings[:output])
      0
    rescue ArgumentError => e
      raise Ibex::Error, "(coverage):1:1: #{e.message}"
    end

    # @rbs (Array[String] arguments) -> Integer
    def run_coverage_check(arguments)
      settings = coverage_check_options(arguments)
      path = single_coverage_path(settings.fetch(:paths), "coverage check")
      report = Coverage::Report.load_file(path)
      state_percentage = coverage_percentage(report.state_hits.length, report.state_count)
      production_percentage = coverage_percentage(report.production_hits.length, report.production_count)
      passed = state_percentage >= settings.fetch(:min_states) &&
               production_percentage >= settings.fetch(:min_productions)
      summary = format(
        "coverage %<status>s: states %<states>.2f%% (%<state_hits>d/%<state_total>d), " \
        "productions %<productions>.2f%% (%<production_hits>d/%<production_total>d)",
        status: passed ? "ok" : "failed",
        states: state_percentage,
        state_hits: report.state_hits.length,
        state_total: report.state_count,
        productions: production_percentage,
        production_hits: report.production_hits.length,
        production_total: report.production_count
      )
      (passed ? @stdout : @stderr).puts(summary)
      passed ? 0 : 1
    end

    # @rbs (Array[String] arguments, String command, String operands) -> coverage_output_options
    def coverage_output_options(arguments, command, operands)
      settings = { paths: [] } #: coverage_output_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex coverage #{command} #{operands} [-o FILE]"
        options.on("-o FILE", "--output=FILE", "write atomically to FILE") { |value| settings[:output] = value }
      end
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (Array[String] arguments) -> coverage_check_options
    def coverage_check_options(arguments)
      settings = { paths: [], min_states: 0.0, min_productions: 0.0 } #: coverage_check_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex coverage check REPORT [thresholds]"
        options.on("--min-states=PERCENT", Float, "minimum visited states") do |value|
          settings[:min_states] = coverage_threshold(value, "min-states")
        end
        options.on("--min-productions=PERCENT", Float, "minimum reduced productions") do |value|
          settings[:min_productions] = coverage_threshold(value, "min-productions")
        end
      end
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (Float value, String name) -> Float
    def coverage_threshold(value, name)
      return value if value.finite? && value >= 0.0 && value <= 100.0

      raise OptionParser::InvalidArgument, "--#{name} must be between 0 and 100"
    end

    # @rbs (Integer covered, Integer total) -> Float
    def coverage_percentage(covered, total)
      return 100.0 if total.zero?

      covered.fdiv(total) * 100.0
    end

    # @rbs (Array[String] arguments, String command) -> String
    def single_coverage_path(arguments, command)
      return arguments.first if arguments.length == 1

      raise Ibex::Error, "(cli):1:1: #{command} requires exactly one input"
    end

    # @rbs (Array[String] inputs, String? output) -> void
    def reject_coverage_output_collision(inputs, output)
      return unless output
      return unless inputs.any? { |input| same_file_target?(input, output) }

      raise Ibex::Error, "(cli):1:1: coverage input and output paths must be distinct"
    end

    # @rbs (Coverage::Report report, String? output) -> void
    def write_coverage_report(report, output)
      source = report.to_json
      return @stdout.write(source) unless output

      atomic_write_coverage(output, source)
    end

    # @rbs (String path, String source) -> void
    def atomic_write_coverage(path, source)
      target_path = File.symlink?(path) ? File.realpath(path) : path
      directory = File.dirname(File.expand_path(target_path))
      basename = File.basename(target_path)
      Tempfile.create([".#{basename}.", ".tmp"], directory) do |temporary|
        temporary.binmode
        temporary.write(source)
        temporary.flush
        temporary.fsync
        temporary.chmod(coverage_file_mode(target_path))
        temporary.close
        File.rename(temporary.path, target_path)
      end
    end

    # @rbs (String path) -> Integer
    def coverage_file_mode(path)
      return File.stat(path).mode & 0o777 if File.exist?(path)

      0o666 & ~File.umask
    end
  end
end
