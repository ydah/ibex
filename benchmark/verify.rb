#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "json_schemer"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ibex"
require_relative "support/benchmark_artifact"

module BenchmarkVerification
  ROOT = File.expand_path("..", __dir__)

  module_function

  def run(argv)
    raise ArgumentError, "usage: benchmark/verify.rb ARTIFACT.json" unless argv.length == 1

    baseline = JSON.parse(File.read(File.expand_path(argv.fetch(0), ROOT)))
    validate!(baseline)
    observed = BenchmarkSupport::Artifact.new(ROOT, options_from(baseline)).run
    observed_document = stringify(observed)
    validate!(observed_document)
    expected_projection = deterministic_projection(baseline)
    observed_projection = deterministic_projection(observed_document)
    raise "benchmark structure or digest drifted from the baseline" unless observed_projection == expected_projection

    puts "benchmark artifact schema and deterministic structure verified"
  end

  def validate!(document)
    version = document.fetch("schema_version")
    schema_path = File.join(ROOT, "schema/benchmark-v#{version}.schema.json")
    raise "unsupported benchmark schema version #{version.inspect}" unless File.file?(schema_path)

    schema = JSON.parse(File.read(schema_path))
    resolver = lambda do |uri|
      path = File.join(ROOT, "schema", File.basename(uri.path))
      JSON.parse(File.read(path)) if File.file?(path)
    end
    errors = JSONSchemer.schema(schema, ref_resolver: resolver).validate(document).to_a
    return if errors.empty?

    raise "invalid benchmark artifact:\n#{errors.map { |error| error.fetch('error') }.join("\n")}"
  end

  def options_from(baseline)
    configuration = baseline.fetch("configuration")
    {
      grammar: configuration.fetch("grammar"),
      input: configuration.fetch("input"),
      seed: configuration.fetch("seed"),
      iterations: 1,
      runtime_iterations: 1,
      json: true,
      output: nil,
      schema_version: baseline.fetch("schema_version")
    }
  end

  def deterministic_projection(document)
    configuration = document.fetch("configuration")
    {
      "configuration" => configuration.slice("grammar", "input", "seed"),
      "structure" => document.fetch("structure"),
      "digests" => document.fetch("digests")
    }
  end

  def stringify(value)
    JSON.parse(JSON.generate(value))
  end
end

BenchmarkVerification.run(ARGV) if $PROGRAM_NAME == __FILE__
