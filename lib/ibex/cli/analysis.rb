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
    #   type analysis_options = Hash[Symbol, untyped]
    #   private def normalize_grammar_path: (String) -> IR::Grammar
    #   private def set_configuration_option: (Symbol, Object?) -> void
    #   private def local_configuration_value: (Hash[Symbol, untyped], String) -> untyped
    #   private def set_local_configuration_option: (Hash[Symbol, untyped], Symbol, untyped) -> void

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

      algorithm = settings.fetch(:algorithm)
      before = load_analysis_automaton(paths.fetch(0), algorithm, explicit: algo_set?(settings))
      after = load_analysis_automaton(paths.fetch(1), algorithm, explicit: algo_set?(settings))
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

      automaton = load_analysis_automaton(paths.fetch(0), settings.fetch(:algorithm), explicit: algo_set?(settings))
      report = Metrics.new(automaton).to_h
      write_analysis_report(report, settings.fetch(:format))
      0
    end

    # @rbs (Array[String] arguments, String command, operands: String) -> Hash[Symbol, untyped]
    def analysis_options(arguments, command, operands:)
      settings = {
        paths: [], algorithm: Configuration::Registry.fetch("parser.algorithm").default,
        mode: Configuration::Registry.fetch("grammar.mode").default, format: "json", configuration_explicit: []
      } #: Hash[Symbol, untyped]
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex #{command} [options] #{operands}"
        options.on(
          "--algorithm=NAME", Configuration::Registry::CLI_ALGORITHM_VALUES, "algorithm for grammar inputs"
        ) do |value|
          set_local_configuration_option(settings, :algorithm, value.to_sym)
        end
        options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
          set_local_configuration_option(settings, :mode, value.to_sym)
          set_configuration_option(:mode, value.to_sym)
        end
        options.on("--format=FORMAT", %w[json text], "json or text") { |value| settings[:format] = value }
        options.on("--help", "show help") { settings[:help] = options.to_s }
      end
      settings[:paths] = parser.parse(arguments)
      settings[:algorithm] = local_configuration_value(settings, "parser.algorithm")
      settings
    end

    # @rbs (String path, Symbol algorithm, explicit: bool) -> IR::Automaton
    def load_analysis_automaton(path, algorithm, explicit:)
      source = File.binread(path)
      if source.lstrip.start_with?("{")
        value = IR::Validator.validate(source)
        if value.is_a?(IR::Automaton)
          raise Ibex::Error, "(cli):1:1: --algorithm cannot be combined with Automaton IR analysis input" if explicit

          return value
        end
        return build_analysis_automaton(value, algorithm, explicit) if value.is_a?(IR::Grammar)

        raise Ibex::Error, "#{path}:1:1: analysis does not accept Lexer IR"
      end

      build_analysis_automaton(normalize_grammar_path(path), algorithm, explicit)
    end

    # @rbs (IR::Grammar grammar, Symbol algorithm, bool algorithm_explicit) -> IR::Automaton
    def build_analysis_automaton(grammar, algorithm, algorithm_explicit)
      explicit_keys = algorithm_explicit ? [:algorithm] : [] #: Array[Symbol]
      active = activate_analysis_grammar(
        grammar, options: { algorithm: algorithm }, explicit_keys: explicit_keys
      )
      LALR::Builder.new(
        active, algorithm: configuration_value("parser.algorithm"),
                entry_isolation: configuration_value("parser.entries") == :isolated
      ).build
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

    # @rbs (Hash[Symbol, untyped] settings) -> bool
    def algo_set?(settings)
      settings.fetch(:configuration_explicit).include?(:algorithm)
    end

    # @rbs!
    #   private def activate_analysis_grammar: (IR::Grammar, ?options: Hash[Symbol, untyped],
    #     ?explicit_keys: Array[Symbol]) -> IR::Grammar
    #   private def configuration_value: (String) -> untyped
  end
end
