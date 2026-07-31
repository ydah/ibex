# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../verify"
require_relative "../ir"

module Ibex
  # CLI entry point for bounded, independent Automaton IR verification.
  module CLIVerify
    # @rbs!
    #   type verify_options = {
    #     paths: Array[String],
    #     strict: bool,
    #     max_states: Integer,
    #     max_items: Integer,
    #     ?grammar: String,
    #     format: String
    #   }

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_verify_command(arguments)
      settings = verify_options(arguments)
      operands = settings.fetch(:paths)
      raise Ibex::Error, "(verify):1:1: verify requires exactly one Automaton IR file" unless operands.length == 1

      automaton = load_verify_automaton(operands.fetch(0))
      verify_supplied_grammar!(automaton, settings[:grammar]) if settings[:grammar]
      result = Verify::Verifier.new(
        automaton,
        strict: settings.fetch(:strict),
        max_states: settings.fetch(:max_states),
        max_items: settings.fetch(:max_items)
      ).verify
      write_verify_result(result, settings.fetch(:format))
      result.valid? ? 0 : 1
    rescue Verify::BudgetExceeded => e
      violations = [] #: Array[Verify::Violation]
      report = {
        ibex_report: "verify", schema_version: 1, result: "budget_exhausted",
        strict: settings&.fetch(:strict, false), bounds: e.bounds, violations: violations
      }
      @stdout.puts(JSON.pretty_generate(report))
      2
    end

    # @rbs (Array[String] arguments) -> verify_options
    def verify_options(arguments)
      settings = {
        paths: [], strict: false, max_states: 100_000, max_items: 1_000_000, format: "json"
      } #: verify_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex verify [options] AUTOMATON.json"
        options.on("--strict", "include completeness and table-bisimulation checks") { settings[:strict] = true }
        options.on("--grammar=GRAMMAR", "require an exact embedded Grammar IR match") do |value|
          settings[:grammar] = value
        end
        options.on("--max-states=N", Integer, "maximum independently derived states") do |value|
          settings[:max_states] = positive_verify_budget(value, "max-states")
        end
        options.on("--max-items=N", Integer, "maximum independently derived items") do |value|
          settings[:max_items] = positive_verify_budget(value, "max-items")
        end
        options.on("--format=FORMAT", %w[json text], "json or text") { |value| settings[:format] = value }
      end
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (String path) -> IR::Automaton
    def load_verify_automaton(path)
      value = IR::Validator.validate(File.binread(path))
      return value if value.is_a?(IR::Automaton)

      raise Ibex::Error, "#{path}:1:1: verify requires Automaton IR"
    end

    # @rbs (IR::Automaton automaton, String path) -> void
    def verify_supplied_grammar!(automaton, path)
      value = IR::Validator.validate(File.binread(path))
      raise Ibex::Error, "#{path}:1:1: --grammar requires Grammar IR" unless value.is_a?(IR::Grammar)
      return if IR::Serialize.dump(value) == IR::Serialize.dump(automaton.grammar)

      raise Ibex::Error, "#{path}:1:1: Grammar IR does not match the automaton's embedded grammar"
    end

    # @rbs (Verify::Result result, String format) -> void
    def write_verify_result(result, format)
      if format == "json"
        @stdout.puts(JSON.pretty_generate(result.to_h))
        return
      end

      @stdout.puts("result=#{result.valid? ? 'valid' : 'invalid'} algorithm=#{result.algorithm}")
      result.violations.each do |violation|
        @stdout.puts("#{violation.id} #{violation.location}: #{violation.message}")
      end
    end

    # @rbs (Integer value, String name) -> Integer
    def positive_verify_budget(value, name)
      return value if value.positive?

      raise OptionParser::InvalidArgument, "--#{name} must be positive"
    end
  end
end
