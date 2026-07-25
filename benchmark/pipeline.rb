#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"
require_relative "support/benchmark_artifact"
require_relative "support/peak_rss"

module PipelineBenchmark
  ROOT = File.expand_path("..", __dir__)
  DEFAULT_GRAMMAR = "benchmark/grammars/representative.y"
  DEFAULT_INPUT = "benchmark/grammars/representative.input"
  DEFAULTS = {
    grammar: DEFAULT_GRAMMAR,
    input: DEFAULT_INPUT,
    iterations: 1,
    runtime_iterations: 100,
    seed: 12_345,
    json: false,
    output: nil
  }.freeze

  module_function

  def run(argv)
    options = parse_options(argv)
    report = nil
    peak_rss = BenchmarkSupport::PeakRSS.observe do
      report = BenchmarkSupport::Artifact.new(ROOT, options).run
    end
    report.fetch(:measurements)[:peak_rss_bytes] = peak_rss
    json = JSON.generate(report)
    write_output(options[:output], json) if options[:output]
    puts render_output(report, json: options.fetch(:json))
  end

  def parse_options(argv)
    options = DEFAULTS.dup
    OptionParser.new do |parser|
      parser.banner = "Usage: benchmark/pipeline.rb [options]"
      parser.on("--grammar PATH", "benchmark grammar relative to the repository") { |value| options[:grammar] = value }
      parser.on("--input PATH", "runtime input relative to the repository") { |value| options[:input] = value }
      parser.on("--iterations N", Integer, "complete builds to measure") { |value| options[:iterations] = value }
      parser.on("--runtime-iterations N", Integer, "generated-parser runs to measure") do |value|
        options[:runtime_iterations] = value
      end
      parser.on("--seed N", Integer, "fixed workload seed") { |value| options[:seed] = value }
      parser.on("--json", "emit an ibex_benchmark v1 JSON document") { options[:json] = true }
      parser.on("--output PATH", "write the JSON artifact to PATH") { |value| options[:output] = value }
    end.parse!(argv)
    raise OptionParser::InvalidArgument, "iterations must be positive" unless options.fetch(:iterations).positive?
    unless options.fetch(:runtime_iterations).positive?
      raise OptionParser::InvalidArgument, "runtime iterations must be positive"
    end

    options
  end

  def write_output(path, output)
    absolute = File.expand_path(path, ROOT)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, "#{output}\n")
  end

  def render_output(report, json:)
    json ? JSON.generate(report) : text_report(report)
  end

  def text_report(report)
    structure = report.fetch(:structure)
    measurements = report.fetch(:measurements)
    runtime = measurements.fetch(:runtime_parse_ms)
    lines = [
      "Ibex representative benchmark (schema v#{report.fetch(:schema_version)})",
      "productions: #{structure.fetch(:productions)}",
      "canonical states: #{structure.fetch(:canonical_intermediate_states)}",
      "final states: #{structure.fetch(:final_states)}",
      "generation: #{format('%.3f', measurements.fetch(:generation_ms))} ms",
      "runtime parse (plain): #{format('%.3f', runtime.fetch(:plain))} ms",
      "runtime parse (compact): #{format('%.3f', runtime.fetch(:compact))} ms",
      "peak RSS: #{measurements.fetch(:peak_rss_bytes) || 'unavailable'} bytes",
      "stage averages:"
    ]
    measurements.fetch(:stage_ms).each do |stage, value|
      lines << format("  %<stage>-18s %<value>8.3f ms", stage: stage, value: value)
    end
    lines << "artifact digest: #{report.fetch(:digests).fetch(:artifact_sha256)}"
    lines.join("\n")
  end
end

PipelineBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
