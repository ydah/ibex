# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../equiv"

module Ibex
  # CLI entry point for bounded language comparison.
  module CLIEquiv
    # @rbs!
    #   type equiv_options = {
    #     paths: Array[String],
    #     sample_count: Integer,
    #     seed: Integer,
    #     max_tokens: Integer,
    #     max_configurations: Integer,
    #     max_actions: Integer,
    #     max_stack: Integer,
    #     algorithm: Symbol,
    #     mode: Symbol,
    #     format: String,
    #     rule_map: Hash[String, String]
    #   }
    #   private def normalize_grammar_path: (String) -> IR::Grammar

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_equiv_command(arguments)
      settings = equiv_options(arguments)
      paths = settings.fetch(:paths)
      raise Ibex::Error, "(equiv):1:1: equiv requires exactly two grammar or IR files" unless paths.length == 2

      left = load_equiv_automaton(paths.fetch(0), settings.fetch(:algorithm))
      right = load_equiv_automaton(paths.fetch(1), settings.fetch(:algorithm))
      comparison = Equiv.new(
        left, right,
        sample_count: settings.fetch(:sample_count), seed: settings.fetch(:seed),
        max_tokens: settings.fetch(:max_tokens), max_configurations: settings.fetch(:max_configurations),
        max_actions: settings.fetch(:max_actions), max_stack: settings.fetch(:max_stack),
        rule_map: settings.fetch(:rule_map)
      )
      write_equiv_report(comparison.run, settings.fetch(:format))
      0
    rescue Equiv::Difference => e
      write_equiv_report(e.details, settings&.fetch(:format) || "json")
      1
    rescue Equiv::BudgetExceeded => e
      report = { ibex_report: "equiv", schema_version: 1 }.merge(e.details)
      write_equiv_report(report, settings&.fetch(:format) || "json")
      2
    end

    # @rbs (Array[String] arguments) -> equiv_options
    def equiv_options(arguments)
      settings = {
        paths: [], sample_count: 100, seed: 0, max_tokens: 8, max_configurations: 50_000,
        max_actions: Equiv::DEFAULT_MAX_ACTIONS, max_stack: Equiv::DEFAULT_MAX_STACK,
        algorithm: :lalr, mode: :default, format: "json", rule_map: {}
      } #: equiv_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex equiv [options] LEFT RIGHT"
        add_equiv_search_options(options, settings)
        options.on("--algorithm=NAME", %w[slr lalr ielr lr1], "algorithm for grammar inputs") do |value|
          settings[:algorithm] = value.to_sym
        end
        options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
          settings[:mode] = value.to_sym
          @options[:mode] = value.to_sym
        end
        options.on("--map=OLD=NEW", "declare a nonterminal correspondence; repeatable") do |value|
          old_name, new_name = value.split("=", 2)
          if old_name.nil? || old_name.empty? || new_name.nil? || new_name.empty?
            raise OptionParser::InvalidArgument, "--map must be OLD=NEW"
          end

          settings.fetch(:rule_map)[old_name] = new_name
        end
        options.on("--format=FORMAT", %w[json text], "json or text") { |value| settings[:format] = value }
      end
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (OptionParser options, equiv_options settings) -> void
    def add_equiv_search_options(options, settings)
      options.on("--samples=N", Integer, "samples generated in each direction") do |value|
        settings[:sample_count] = positive_equiv_option(value, "samples")
      end
      options.on("--seed=N", Integer, "deterministic sampling seed") { |value| settings[:seed] = value }
      options.on("--max-tokens=N", Integer, "maximum counterexample length") do |value|
        settings[:max_tokens] = positive_equiv_option(value, "max-tokens")
      end
      options.on("--max-configurations=N", Integer, "product-state exploration budget") do |value|
        settings[:max_configurations] = positive_equiv_option(value, "max-configurations")
      end
      options.on("--max-actions=N", Integer, "actions per simulated token sequence") do |value|
        settings[:max_actions] = positive_equiv_option(value, "max-actions")
      end
      options.on("--max-stack=N", Integer, "simulated parser stack depth") do |value|
        settings[:max_stack] = positive_equiv_option(value, "max-stack")
      end
    end

    # @rbs (String path, Symbol algorithm) -> IR::Automaton
    def load_equiv_automaton(path, algorithm)
      source = File.binread(path)
      if source.lstrip.start_with?("{")
        value = IR::Validator.validate(source)
        return value if value.is_a?(IR::Automaton)
        return LALR::Builder.new(value, algorithm: algorithm).build if value.is_a?(IR::Grammar)

        raise Ibex::Error, "#{path}:1:1: equiv does not accept Lexer IR"
      end

      LALR::Builder.new(normalize_grammar_path(path), algorithm: algorithm).build
    end

    # @rbs (Hash[Symbol, untyped] report, String format) -> void
    def write_equiv_report(report, format)
      if format == "json"
        @stdout.puts(JSON.pretty_generate(report))
      else
        @stdout.puts("result=#{report.fetch(:result)}")
        @stdout.puts("witness=#{report[:witness].inspect}") if report[:witness]
        @stdout.puts(report.fetch(:statement))
      end
    end

    # @rbs (Integer value, String name) -> Integer
    def positive_equiv_option(value, name)
      return value if value.positive?

      raise OptionParser::InvalidArgument, "--#{name} must be positive"
    end
  end
end
