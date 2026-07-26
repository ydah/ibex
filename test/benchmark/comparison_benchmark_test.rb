# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/comparison"
require "json"
require "json_schemer"

class ComparisonBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA = File.join(ROOT, "schema/performance-comparison-v1.schema.json")

  def test_public_run_requires_ten_isolated_processes
    error = assert_raises(OptionParser::InvalidArgument) do
      PerformanceComparison.parse_options(["--runs", "9"])
    end

    assert_includes error.message, "at least ten isolated runs"
    assert_includes [true, false], BenchmarkSupport::ComparisonWorker.yjit_enabled?
  end

  def test_bootstrap_comparison_is_deterministic
    first = BenchmarkSupport::ComparisonStatistics.compare(
      [2.0, 2.1, 2.2],
      [1.0, 1.1, 1.2],
      seed: 12_345,
      samples: 1_000
    )
    second = BenchmarkSupport::ComparisonStatistics.compare(
      [2.0, 2.1, 2.2],
      [1.0, 1.1, 1.2],
      seed: 12_345,
      samples: 1_000
    )

    assert_equal first, second
    assert_equal 1.909091, first.fetch(:ibex_to_racc_ratio)
    assert_operator first.dig(:bootstrap_95_percent, :lower), :>, 1.0
    refute first.fetch(:target_met)
  end

  def test_black_box_workers_return_equivalent_results
    options = {
      warmup: 0,
      runtime_iterations: 1,
      workload_seed: 12_345
    }
    generation = %w[ibex racc].map do |implementation|
      PerformanceComparison.worker_observation(implementation, "cold_generation", options)
    end
    runtime = %w[ibex racc].flat_map do |implementation|
      %w[warm_runtime_end_to_end_reuse warm_runtime_tokens_new_instance].map do |scenario|
        PerformanceComparison.worker_observation(implementation, scenario, options)
      end
    end

    generation.each do |entry|
      assert_operator entry.fetch("elapsed_ms"), :>, 0
      assert_operator entry.fetch("generated_bytes"), :>, 0
    end
    runtime.each do |entry|
      assert_operator entry.fetch("elapsed_ms_per_parse"), :>, 0
      assert_operator entry.fetch("allocated_objects_per_parse"), :>=, 0
      assert_includes %w[native ruby], entry.fetch("runtime_backend")
    end
    assert_equal 1, runtime.map { |entry| entry.fetch("result_sha256") }.uniq.length
    assert_equal 1, runtime.map { |entry| entry.fetch("behavior_sha256") }.uniq.length
  end

  def test_report_shape_validates_against_the_public_schema
    options = PerformanceComparison::DEFAULTS.merge(
      runs: 10,
      warmup: 0,
      runtime_iterations: 1,
      bootstrap_samples: 1_000
    )
    observations = PerformanceComparison::SCENARIOS.to_h do |scenario|
      values = %w[ibex racc].to_h do |implementation|
        [implementation, Array.new(10) { fake_observation(scenario, implementation) }]
      end
      [scenario, values]
    end
    report = PerformanceComparison.report_document(options, observations)
    errors = JSONSchemer.schema(JSON.parse(File.read(SCHEMA))).validate(JSON.parse(JSON.generate(report))).to_a

    assert_empty errors
    assert_equal "ibex_racc_performance_comparison", report.fetch(:artifact)
    assert report.dig(:scenarios, :warm_runtime_tokens_reuse, :comparison, :result_equivalent)
  end

  private

  def fake_observation(scenario, implementation)
    common = {
      "implementation" => implementation,
      "scenario" => scenario,
      "generated_bytes" => implementation == "ibex" ? 120 : 100
    }
    return common.merge("elapsed_ms" => implementation == "ibex" ? 2.0 : 1.0) if scenario == "cold_generation"

    common.merge(
      "elapsed_ms_per_parse" => implementation == "ibex" ? 2.0 : 1.0,
      "allocated_objects_per_parse" => implementation == "ibex" ? 20.0 : 10.0,
      "result_sha256" => "c" * 64,
      "behavior_sha256" => "d" * 64,
      "runtime_backend" => implementation == "ibex" ? "ruby" : "native"
    )
  end
end
