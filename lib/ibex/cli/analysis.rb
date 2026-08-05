# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../diff"
require_relative "../metrics"

module Ibex
  # CLI entry points for deterministic grammar diff and metrics reports.
  module CLIAnalysis
    # @rbs!
    #   type analysis_options = {
    #     paths: Array[String],
    #     algorithm: Symbol,
    #     mode: Symbol,
    #     format: String,
    #     ?help: String
    #   }
    #   private def normalize_grammar_path: (String) -> IR::Grammar
    #   private def configuration_value: (String) -> untyped
    #   private def mark_configuration_option: (Symbol) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_diff_command(arguments)
      settings = analysis_options(arguments, "diff", operands: "OLD NEW")
      if settings[:help]
        @stdout.puts(settings.fetch(:help))
        return 0
      end
      paths = settings.fetch(:paths)
      raise Ibex::Error, "(diff):1:1: diff requires exactly two grammar or IR files" unless paths.length == 2

      algorithm = configuration_value("parser.algorithm")
      before = load_analysis_automaton(paths.fetch(0), algorithm)
      after = load_analysis_automaton(paths.fetch(1), algorithm)
      report = Diff.new(before, after).to_h
      write_analysis_report(report, settings.fetch(:format))
      0
    end

    # @rbs (Array[String] arguments) -> Integer
    def run_metrics_command(arguments)
      settings = analysis_options(arguments, "metrics", operands: "GRAMMAR")
      if settings[:help]
        @stdout.puts(settings.fetch(:help))
        return 0
      end
      paths = settings.fetch(:paths)
      raise Ibex::Error, "(metrics):1:1: metrics requires exactly one grammar or IR file" unless paths.length == 1

      automaton = load_analysis_automaton(paths.fetch(0), configuration_value("parser.algorithm"))
      report = Metrics.new(automaton).to_h
      write_analysis_report(report, settings.fetch(:format))
      0
    end

    # @rbs (Array[String] arguments, String command, operands: String) -> analysis_options
    def analysis_options(arguments, command, operands:)
      settings = {
        paths: [], algorithm: Configuration::Registry.fetch("parser.algorithm").default,
        mode: Configuration::Registry.fetch("grammar.mode").default, format: "json"
      } #: analysis_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex #{command} [options] #{operands}"
        options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "algorithm for grammar inputs") do |value|
          settings[:algorithm] = value.to_sym
          mark_configuration_option(:algorithm)
        end
        options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
          settings[:mode] = value.to_sym
          mark_configuration_option(:mode)
        end
        options.on("--format=FORMAT", %w[json text], "json or text") { |value| settings[:format] = value }
        options.on("--help", "show help") { settings[:help] = options.to_s }
      end
      settings[:paths] = parser.parse(arguments)
      @options[:algorithm] = settings.fetch(:algorithm)
      @options[:mode] = settings.fetch(:mode)
      settings
    end

    # @rbs (String path, Symbol algorithm) -> IR::Automaton
    def load_analysis_automaton(path, algorithm)
      source = File.binread(path)
      if source.lstrip.start_with?("{")
        value = IR::Validator.validate(source)
        return value if value.is_a?(IR::Automaton)
        return LALR::Builder.new(value, algorithm: algorithm).build if value.is_a?(IR::Grammar)

        raise Ibex::Error, "#{path}:1:1: analysis does not accept Lexer IR"
      end

      LALR::Builder.new(normalize_grammar_path(path), algorithm: algorithm).build
    end

    # @rbs (Hash[Symbol, untyped] report, String format) -> void
    def write_analysis_report(report, format)
      if format == "json"
        @stdout.puts(JSON.pretty_generate(report))
      elsif report.fetch(:ibex_report) == "metrics"
        @stdout.puts("states=#{report.dig(:automaton, :states)} rules=#{report.dig(:grammar, :rules)} " \
                     "alternatives=#{report.dig(:grammar, :alternatives)}")
      else
        %i[symbols rules conflicts warnings].each do |section|
          values = report.fetch(section)
          @stdout.puts("#{section}: +#{values.fetch(:added).length} " \
                       "-#{values.fetch(:removed).length} ~#{values.fetch(:changed).length}")
        end
      end
    end
  end
end
