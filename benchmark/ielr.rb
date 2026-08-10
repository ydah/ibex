#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "rbconfig"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"
require_relative "../tool/profile/construction_profiler"

# Structural, reproducible direct-IELR versus partition-IELR observations.
# Timings are retained as host observations and are never a release gate.
module IELRBenchmark
  ROOT = File.expand_path("..", __dir__)
  DEFAULT_WALL_SECONDS = 30.0
  FIXTURE_GLOB = File.join(ROOT, "test/fixtures/ielr/*.y")
  DEFAULT_PATHS = (Dir.glob(FIXTURE_GLOB) + Dir.glob(File.join(ROOT, "gallery/*/grammar.y"))).sort.freeze

  module_function

  # rubocop:disable Metrics/MethodLength -- this is the complete small benchmark report builder.
  def build(root: ROOT, paths: DEFAULT_PATHS, wall_seconds: DEFAULT_WALL_SECONDS)
    expanded = paths.map { |path| File.expand_path(path, root) }.uniq.sort
    workloads = expanded.flat_map do |path|
      source = File.binread(path)
      grammar = normalize(source, path)
      %i[partition direct].map do |strategy|
        run = profile(grammar, strategy, wall_seconds).fetch("shared")
        {
          "id" => path.delete_prefix("#{root}/").sub(/\.y\z/, ""),
          "path" => path.delete_prefix("#{root}/"),
          "source_sha256" => Digest::SHA256.hexdigest(source),
          "strategy" => strategy.to_s,
          "status" => run.fetch("status"),
          "structural" => run.fetch("structural"),
          "conflicts" => run.fetch("conflicts"),
          "observations" => run.fetch("observations")
        }
      end
    end

    {
      "ibex_report" => "ielr_benchmark",
      "schema_version" => 1,
      "trust" => "internal_local_observation",
      "environment" => environment,
      "configuration" => {
        "wall_seconds_per_run" => wall_seconds,
        "workload_count" => expanded.length,
        "workload_selection" => expanded.map { |path| path.delete_prefix("#{root}/") }
      },
      "workloads" => workloads,
      "limitations" => [
        "Elapsed time is host-dependent diagnostic evidence and is not a release gate.",
        "A completed bounded probe does not establish canonical adequacy or semantic equivalence.",
        "The direct strategy remains experimental and the I001 decision remains NO-GO."
      ]
    }
  end
  # rubocop:enable Metrics/MethodLength

  def normalize(source, path)
    mode = source.include?("pragma extended") ? :extended : :default
    ast = Ibex::Frontend::Parser.new(source, file: path, mode: mode).parse
    Ibex::Normalizer.new(ast, mode: mode).normalize
  end

  def profile(grammar, strategy, wall_seconds)
    runs = Ibex::Profile::ConstructionProfiler.new(
      wall_seconds: wall_seconds, ielr_strategy: strategy
    ).profile(grammar)
    runs.to_h do |run|
      [run.fetch("entry_mode"), run]
    end
  end

  def environment
    {
      "ruby_engine" => RUBY_ENGINE,
      "ruby_version" => RUBY_VERSION,
      "ruby_platform" => RUBY_PLATFORM,
      "host_os" => RbConfig::CONFIG.fetch("host_os"),
      "host_cpu" => RbConfig::CONFIG.fetch("host_cpu")
    }
  end

  def deterministic_projection(document)
    {
      "configuration" => document.fetch("configuration"),
      "workloads" => document.fetch("workloads").map do |workload|
        workload.slice("id", "path", "source_sha256", "strategy", "status", "structural", "conflicts")
      end
    }
  end

  def parse_options(arguments)
    options = { wall_seconds: DEFAULT_WALL_SECONDS, output: nil }
    OptionParser.new do |parser|
      parser.banner = "Usage: bundle exec ruby benchmark/ielr.rb [options]"
      parser.on("--wall-seconds=SECONDS", Float, "per-build diagnostic wall-time limit") do |value|
        options[:wall_seconds] = value
      end
      parser.on("--output=PATH", "write JSON to PATH") { |value| options[:output] = value }
    end.parse!(arguments)
    raise OptionParser::InvalidArgument, "wall-seconds must be positive" unless options.fetch(:wall_seconds).positive?

    options
  end

  def run(arguments)
    options = parse_options(arguments)
    report = build(wall_seconds: options.fetch(:wall_seconds))
    output = "#{JSON.pretty_generate(report)}\n"
    File.binwrite(File.expand_path(options.fetch(:output), ROOT), output) if options[:output]
    puts output
  end
end

IELRBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
