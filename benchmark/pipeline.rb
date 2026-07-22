#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

module PipelineBenchmark
  STAGES = %i[parse normalize lalr table codegen_with_tables].freeze
  DEFAULTS = { rules: 200, iterations: 5, seed: 12_345, json: false }.freeze

  module_function

  def run(argv)
    options = parse_options(argv)
    source = grammar_source(options.fetch(:rules), options.fetch(:seed))
    timings = STAGES.to_h { |stage| [stage, []] }
    result = nil
    digest = nil
    options.fetch(:iterations).times do
      result = run_once(source, timings)
      current_digest = result_digest(result)
      raise "pipeline output changed between identical iterations" if digest && digest != current_digest

      digest = current_digest
    end
    report = report_for(options, result, timings, digest)
    puts(options.fetch(:json) ? JSON.generate(report) : text_report(report))
  end

  def parse_options(argv)
    options = DEFAULTS.dup
    OptionParser.new do |parser|
      parser.banner = "Usage: ruby benchmark/pipeline.rb [options]"
      parser.on("--rules N", Integer, "number of chained grammar rules") { |value| options[:rules] = value }
      parser.on("--iterations N", Integer, "number of measured complete builds") do |value|
        options[:iterations] = value
      end
      parser.on("--seed N", Integer, "fixed grammar seed") { |value| options[:seed] = value }
      parser.on("--json", "emit machine-readable JSON") { options[:json] = true }
    end.parse!(argv)
    raise OptionParser::InvalidArgument, "rules must be at least 2" if options.fetch(:rules) < 2
    raise OptionParser::InvalidArgument, "iterations must be positive" unless options.fetch(:iterations).positive?

    options
  end

  def grammar_source(rule_count, seed)
    random = Random.new(seed)
    tokens = Array.new(16) { |index| "TOKEN_#{index}" }
    rules = Array.new(rule_count) do |index|
      first, second = tokens.sample(2, random: random)
      rhs = index == rule_count - 1 ? "#{first} | #{second}" : "#{first} node_#{index + 1} | #{second}"
      "node_#{index}: #{rhs}"
    end
    <<~GRAMMAR
      class PipelineBenchmarkParser
      token #{tokens.join(' ')}
      rule
      start: node_0
      #{rules.join("\n")}
      end
    GRAMMAR
  end

  def run_once(source, timings)
    ast = measure(timings[:parse]) { Ibex::Frontend::Parser.new(source, file: "benchmark.y").parse }
    grammar = measure(timings[:normalize]) { Ibex::Normalizer.new(ast).normalize }
    automaton = measure(timings[:lalr]) { Ibex::LALR::Builder.new(grammar).build }
    tables = measure(timings[:table]) { Ibex::Tables.build(automaton, format: :compact) }
    output = measure(timings[:codegen_with_tables]) do
      Ibex::Codegen::Ruby.new(automaton, table: :compact).generate
    end
    { grammar: grammar, automaton: automaton, tables: tables, output: output }
  end

  def measure(samples)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    samples << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    result
  end

  def result_digest(result)
    grammar = Ibex::IR::Serialize.dump(result.fetch(:grammar))
    automaton = Ibex::IR::Serialize.dump(result.fetch(:automaton))
    tables = result.fetch(:tables)
    table_data = [tables.actions.offsets, tables.actions.values, tables.actions.checks,
                  tables.gotos.offsets, tables.gotos.values, tables.gotos.checks, tables.default_actions]
    Digest::SHA256.hexdigest([grammar, automaton, table_data.inspect, result.fetch(:output)].join("\0"))
  end

  def report_for(options, result, timings, digest)
    automaton = result.fetch(:automaton)
    tables = result.fetch(:tables)
    {
      seed: options.fetch(:seed), iterations: options.fetch(:iterations), grammar_rules: options.fetch(:rules),
      productions: automaton.grammar.productions.length, states: automaton.states.length,
      action_cells: tables.actions.checks.compact.length, goto_cells: tables.gotos.checks.compact.length,
      output_bytes: result.fetch(:output).bytesize, result_sha256: digest,
      stage_ms: timings.transform_values { |samples| average_milliseconds(samples) }
    }
  end

  def average_milliseconds(samples)
    ((samples.sum / samples.length) * 1000).round(3)
  end

  def text_report(report)
    headings = %i[seed iterations grammar_rules productions states action_cells goto_cells output_bytes result_sha256]
    lines = ["Ibex whole-builder benchmark"]
    headings.each { |heading| lines << ("#{heading}:".ljust(16) + report.fetch(heading).to_s) }
    lines << "stage averages:"
    report.fetch(:stage_ms).each do |stage, value|
      lines << ("  #{stage}".ljust(16) + format("%<value>8.3f ms", value: value))
    end
    lines.join("\n")
  end
end

PipelineBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
