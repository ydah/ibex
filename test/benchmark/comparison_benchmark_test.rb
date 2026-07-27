# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/comparison"
require "digest"
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

  def test_public_run_validates_environment_and_probe_options
    seed_error = assert_raises(OptionParser::InvalidArgument) do
      PerformanceComparison.parse_options(["--workload-seed", "-1"])
    end
    backend_error = assert_raises(OptionParser::InvalidArgument) do
      PerformanceComparison.parse_options(["--expected-racc-backend", "unknown"])
    end

    assert_includes seed_error.message, "workload seed must not be negative"
    assert_includes backend_error.message, "expected Racc backend"
    assert_equal "native", PerformanceComparison.parse_options([]).fetch(:expected_racc_backend)
    assert_equal(
      "ruby",
      PerformanceComparison.parse_options(["--expected-racc-backend", "ruby"]).fetch(:expected_racc_backend)
    )
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
    skip "runtime allocation counter unavailable" unless TestRuntimeCapabilities.allocation_counter?

    options = {
      warmup: 0,
      runtime_iterations: 1,
      workload_seed: 12_345,
      behavior_probe_iterations: 3
    }
    generation = %w[ibex racc].map do |implementation|
      PerformanceComparison.worker_observation(implementation, "cold_generation", options)
    end
    runtime_scenarios = PerformanceComparison::SCENARIOS - ["cold_generation"]
    runtime = %w[ibex racc].flat_map do |implementation|
      runtime_scenarios.map do |scenario|
        PerformanceComparison.worker_observation(implementation, scenario, options)
      end
    end

    assert_worker_execution_metadata(generation + runtime)
    assert_generation_observations(generation)
    assert_runtime_observations(runtime)
    assert_runtime_digests(runtime)
  end

  def test_result_sequence_digest_covers_each_probe_parse
    original = BenchmarkSupport::ComparisonWorker.result_sequence_digest([1, 2, 3])

    refute_equal original, BenchmarkSupport::ComparisonWorker.result_sequence_digest([1, 9, 3])
  end

  def test_rubyopt_metadata_records_identity_without_exposing_values
    raw = "-I/private/secret -r/private/token --yjit --name=secret"
    metadata = BenchmarkSupport::ComparisonWorker.rubyopt_metadata(raw)

    assert metadata.fetch(:present)
    assert_equal raw.bytesize, metadata.fetch(:bytes)
    assert_equal Digest::SHA256.hexdigest(raw), metadata.fetch(:sha256)
    refute_includes metadata.fetch(:sanitized).join(" "), "private"
    refute_includes metadata.fetch(:sanitized).join(" "), "secret"
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
    assert_same report, PerformanceComparison.validate_report!(report)
    assert_equal "ibex_racc_performance_comparison", report.fetch(:artifact)
    assert report.dig(:scenarios, :warm_runtime_tokens_reuse, :comparison, :result_equivalent)
    assert_equal(
      report.dig(:environment, :git_dirty),
      report.dig(:environment, :git_tracked_dirty) || report.dig(:environment, :git_untracked_dirty)
    )
    refute_empty report.dig(:environment, :kernel_release)
    cpu_model = report.dig(:environment, :cpu_model)
    assert cpu_model.nil? || !cpu_model.empty?
  end

  def test_report_rejects_backend_and_worker_environment_mismatches
    options = PerformanceComparison::DEFAULTS.merge(
      runs: 10,
      warmup: 0,
      runtime_iterations: 1,
      bootstrap_samples: 1_000
    )
    backend_observations = fake_observations
    backend_observations.fetch("warm_runtime_tokens_reuse").fetch("racc").first["runtime_backend"] = "ruby"
    yjit_observations = fake_observations
    yjit_observations.fetch("cold_generation").fetch("ibex").first["yjit_enabled"] =
      !BenchmarkSupport::ComparisonWorker.yjit_enabled?

    backend_error = assert_raises(RuntimeError) do
      PerformanceComparison.report_document(options, backend_observations)
    end
    yjit_error = assert_raises(RuntimeError) do
      PerformanceComparison.report_document(options, yjit_observations)
    end

    assert_includes backend_error.message, "Racc runtime backend"
    assert_includes yjit_error.message, "YJIT state"
  end

  def test_dirty_state_distinguishes_tracked_and_untracked_changes
    assert_equal(
      { git_dirty: true, git_tracked_dirty: true, git_untracked_dirty: true },
      PerformanceComparison.dirty_state([" M tracked.rb", "?? untracked.rb"])
    )
  end

  private

  def assert_worker_execution_metadata(entries)
    entries.each do |entry|
      assert_includes [true, false], entry.fetch("yjit_enabled")
      assert_equal rubyopt_sha256, entry.fetch("rubyopt_sha256")
    end
  end

  def assert_generation_observations(entries)
    entries.each do |entry|
      assert_operator entry.fetch("elapsed_ms"), :>, 0
      assert_operator entry.fetch("generated_bytes"), :>, 0
    end
  end

  def assert_runtime_observations(entries)
    entries.each do |entry|
      assert_operator entry.fetch("elapsed_ms_per_parse"), :>, 0
      assert_operator entry.fetch("allocated_objects_per_parse"), :>=, 0
      assert_includes %w[native ruby], entry.fetch("runtime_backend")
      assert_equal 3, entry.fetch("result_sequence_length")
    end
  end

  def assert_runtime_digests(entries)
    %w[result_sha256 behavior_sha256 result_sequence_sha256].each do |key|
      assert_equal 1, entries.map { |entry| entry.fetch(key) }.uniq.length
    end
  end

  def fake_observations
    PerformanceComparison::SCENARIOS.to_h do |scenario|
      values = %w[ibex racc].to_h do |implementation|
        [implementation, Array.new(10) { fake_observation(scenario, implementation) }]
      end
      [scenario, values]
    end
  end

  def fake_observation(scenario, implementation)
    common = {
      "implementation" => implementation,
      "scenario" => scenario,
      "generated_bytes" => implementation == "ibex" ? 120 : 100,
      "yjit_enabled" => BenchmarkSupport::ComparisonWorker.yjit_enabled?,
      "rubyopt_sha256" => rubyopt_sha256
    }
    return common.merge("elapsed_ms" => implementation == "ibex" ? 2.0 : 1.0) if scenario == "cold_generation"

    common.merge(
      "elapsed_ms_per_parse" => implementation == "ibex" ? 2.0 : 1.0,
      "allocated_objects_per_parse" => implementation == "ibex" ? 20.0 : 10.0,
      "result_sha256" => "c" * 64,
      "behavior_sha256" => "d" * 64,
      "result_sequence_sha256" => "e" * 64,
      "result_sequence_length" => PerformanceComparison::DEFAULTS.fetch(:behavior_probe_iterations),
      "runtime_backend" => implementation == "ibex" ? "ruby" : "native"
    )
  end

  def rubyopt_sha256
    Digest::SHA256.hexdigest(ENV.fetch("RUBYOPT")) if ENV.key?("RUBYOPT")
  end
end
