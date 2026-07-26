#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "etc"
require "json"
require "optparse"
require "rbconfig"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

module ScaleBenchmark
  DEFAULTS = { rules: 500, iterations: 3, json: false }.freeze

  module_function

  def run(argv)
    options = parse_options(argv)
    report = benchmark(options)
    puts(options.fetch(:json) ? JSON.generate(report) : text_report(report))
  end

  def parse_options(argv)
    options = DEFAULTS.dup
    OptionParser.new do |parser|
      parser.banner = "Usage: benchmark/scale.rb [options]"
      parser.on("--rules N", Integer, "recursive rules after the start production") { |value| options[:rules] = value }
      parser.on("--iterations N", Integer, "complete builds to measure") { |value| options[:iterations] = value }
      parser.on("--json", "emit machine-readable JSON") { options[:json] = true }
    end.parse!(argv)
    raise OptionParser::InvalidArgument, "rules must be positive" unless options.fetch(:rules).positive?
    raise OptionParser::InvalidArgument, "iterations must be positive" unless options.fetch(:iterations).positive?

    options
  end

  def benchmark(options)
    source = grammar_source(options.fetch(:rules))
    samples = []
    observed = nil
    digest = nil
    options.fetch(:iterations).times do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      current = build(source)
      samples << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000)
      current_digest = Digest::SHA256.hexdigest(Ibex::IR::Serialize.dump(current.fetch(:automaton)))
      raise "scale benchmark changed between identical iterations" if digest && digest != current_digest

      observed = current
      digest = current_digest
    end
    result = observed || raise("scale benchmark did not run")
    automaton_digest = digest || raise("missing digest")
    report(options, source, samples, result, automaton_digest)
  end

  def grammar_source(rule_count)
    rules = rule_count.times.map do |index|
      target = index == rule_count - 1 ? "TOKEN" : "n#{index + 1}"
      "n#{index}: #{target}"
    end
    <<~GRAMMAR
      class BenchmarkScaleParser
      rule
      start: n0
      #{rules.join("\n")}
      end
    GRAMMAR
  end

  def build(source)
    ast = Ibex::Frontend::Parser.new(source, file: "benchmark/generated-scale.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    builder = Ibex::LALR::Builder.new(grammar)
    automaton = builder.build
    generated = Ibex::Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
    {
      grammar: grammar,
      automaton: automaton,
      metrics: builder.metrics || raise("missing builder metrics"),
      generated: generated
    }
  end

  def report(options, source, samples, observed, digest)
    {
      artifact: "ibex_scale_benchmark",
      schema_version: 1,
      environment: environment,
      configuration: options.slice(:rules, :iterations),
      measurements: measurements(samples),
      structure: structure(observed),
      digests: digests(source, observed, digest)
    }
  end

  def environment
    {
      ruby_engine: RUBY_ENGINE,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      ibex_version: Ibex::VERSION,
      host_os: RbConfig::CONFIG.fetch("host_os"),
      host_cpu: RbConfig::CONFIG.fetch("host_cpu"),
      processors: Etc.nprocessors
    }
  end

  def measurements(samples)
    {
      build_ms_average: (samples.sum / samples.length).round(3),
      build_ms_minimum: samples.min.round(3),
      build_ms_maximum: samples.max.round(3)
    }
  end

  def structure(observed)
    automaton = observed.fetch(:automaton)
    metrics = observed.fetch(:metrics)
    {
      productions: observed.fetch(:grammar).productions.length,
      final_states: automaton.states.length,
      construction_strategy: metrics.strategy.to_s,
      construction_intermediate_states: metrics.construction_states,
      generated_bytes: observed.fetch(:generated).bytesize,
      conflicts: automaton.conflict_summary
    }
  end

  def digests(source, observed, automaton_digest)
    {
      grammar_source_sha256: Digest::SHA256.hexdigest(source),
      automaton_ir_sha256: automaton_digest,
      generated_sha256: Digest::SHA256.hexdigest(observed.fetch(:generated))
    }
  end

  def text_report(report)
    structure = report.fetch(:structure)
    measurements = report.fetch(:measurements)
    range = format(
      "%<minimum>.3f..%<maximum>.3f ms",
      minimum: measurements.fetch(:build_ms_minimum),
      maximum: measurements.fetch(:build_ms_maximum)
    )
    [
      "Ibex generated scale benchmark",
      "productions: #{structure.fetch(:productions)}",
      "construction: #{structure.fetch(:construction_strategy)}",
      "construction states: #{structure.fetch(:construction_intermediate_states)}",
      "final states: #{structure.fetch(:final_states)}",
      "generated bytes: #{structure.fetch(:generated_bytes)}",
      "build average: #{format('%.3f', measurements.fetch(:build_ms_average))} ms",
      "build range: #{range}",
      "automaton digest: #{report.fetch(:digests).fetch(:automaton_ir_sha256)}"
    ].join("\n")
  end
end

ScaleBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
