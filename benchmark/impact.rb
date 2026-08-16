#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "objspace"
require "optparse"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"

module ImpactBenchmark
  DEFAULTS = { grammar: "benchmark/grammars/representative.y", iterations: 3, json: false }.freeze

  module_function

  def run(argv)
    options = parse_options(argv)
    grammar = load_grammar(options.fetch(:grammar))
    samples = options.fetch(:iterations).times.map { measure(grammar) }
    report = {
      artifact: "ibex_impact_benchmark", schema_version: 1,
      configuration: options.slice(:grammar, :iterations),
      measurements: {
        sets_ms_average: average(samples, :sets_ms), graph_ms_average: average(samples, :graph_ms),
        allocated_objects_average: average(samples, :allocated_objects),
        dependency_storage_bytes_average: average(samples, :dependency_storage_bytes)
      },
      structure: {
        symbols: grammar.symbols.length, productions: grammar.productions.length,
        dependency_edges: samples.last.fetch(:dependency_edges), graph_edges: samples.last.fetch(:graph_edges)
      }
    }
    puts(options.fetch(:json) ? JSON.generate(report) : text_report(report))
  end

  def parse_options(argv)
    options = DEFAULTS.dup
    OptionParser.new do |parser|
      parser.banner = "Usage: benchmark/impact.rb [options]"
      parser.on("--grammar PATH", "grammar relative to the repository") { |value| options[:grammar] = value }
      parser.on("--iterations N", Integer, "measurement repetitions") { |value| options[:iterations] = value }
      parser.on("--json", "emit machine-readable JSON") { options[:json] = true }
    end.parse!(argv)
    raise OptionParser::InvalidArgument, "iterations must be positive" unless options.fetch(:iterations).positive?

    options
  end

  def load_grammar(path)
    source = File.binread(File.expand_path(path, File.expand_path("..", __dir__)))
    ast = Ibex::Frontend::Parser.new(source, file: path).parse
    Ibex::Normalizer.new(ast).normalize
  end

  def measure(grammar)
    GC.start
    allocated_before = GC.stat.fetch(:total_allocated_objects)
    sets_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sets = Ibex::Analysis::Sets.new(grammar)
    sets_ms = elapsed_ms(sets_started)
    graph_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    graph = Ibex::Impact::Graph.new(grammar, sets: sets)
    graph_ms = elapsed_ms(graph_started)
    {
      sets_ms: sets_ms, graph_ms: graph_ms,
      allocated_objects: GC.stat.fetch(:total_allocated_objects) - allocated_before,
      dependency_storage_bytes: dependency_storage_bytes(sets),
      dependency_edges: sets.first_dependencies.sum(&:length) + sets.follow_dependencies.sum(&:length),
      graph_edges: graph.edges(:all).length
    }
  end

  def dependency_storage_bytes(sets)
    [sets.first_dependencies, sets.follow_dependencies].sum do |dependencies|
      ObjectSpace.memsize_of(dependencies) + dependencies.sum { |edges| ObjectSpace.memsize_of(edges) }
    end
  end

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3)
  end

  def average(samples, key)
    (samples.sum { |sample| sample.fetch(key) }.to_f / samples.length).round(3)
  end

  def text_report(report)
    measurements = report.fetch(:measurements)
    structure = report.fetch(:structure)
    [
      "Ibex impact benchmark",
      "grammar: #{report.fetch(:configuration).fetch(:grammar)}",
      "symbols: #{structure.fetch(:symbols)}",
      "productions: #{structure.fetch(:productions)}",
      "dependency edges: #{structure.fetch(:dependency_edges)}",
      "graph edges: #{structure.fetch(:graph_edges)}",
      "Sets: #{measurements.fetch(:sets_ms_average)} ms average",
      "Graph: #{measurements.fetch(:graph_ms_average)} ms average",
      "allocated objects: #{measurements.fetch(:allocated_objects_average)} average",
      "dependency storage: #{measurements.fetch(:dependency_storage_bytes_average)} bytes average"
    ].join("\n")
  end
end

ImpactBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
