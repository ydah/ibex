# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "json_schemer"
require_relative "../../benchmark/ielr"

class IELRBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA = JSONSchemer.schema(JSON.parse(File.binread(File.join(ROOT, "schema/ielr-benchmark-v1.schema.json"))))
  FIG1 = File.join(ROOT, "test/fixtures/ielr/fig1.y")

  def test_report_is_schema_valid_and_contains_both_strategies
    report = IELRBenchmark.build(root: ROOT, paths: [FIG1], wall_seconds: 5)

    assert_empty SCHEMA.validate(report).to_a
    assert_equal %w[direct partition], report.fetch("workloads").map { |item| item.fetch("strategy") }.sort
    assert_equal ["test/fixtures/ielr/fig1.y"], report.fetch("configuration").fetch("workload_selection")
    assert_equal 1, report.fetch("configuration").fetch("workload_count")
  end

  def test_deterministic_projection_ignores_host_timing
    first = IELRBenchmark.build(root: ROOT, paths: [FIG1], wall_seconds: 5)
    second = Marshal.load(Marshal.dump(first))
    second.fetch("environment")["ruby_version"] = "other-host"
    second.fetch("workloads").each do |workload|
      workload.dig("observations", "elapsed_seconds")["value"] = 0.0
    end

    assert_equal IELRBenchmark.deterministic_projection(first),
                 IELRBenchmark.deterministic_projection(second)
  end
end
