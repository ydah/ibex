# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/cst"

class CSTBenchmarkTest < Minitest::Test
  def test_report_includes_normal_recovery_and_identity_measurements
    report = CSTBenchmark.benchmark(rules: 2, iterations: 1, runs: 2, seed: 12_345, output: nil)
    recovery = report.fetch(:recovery)

    assert_equal 4, report.fetch(:version)
    assert_operator report.fetch(:cst_overhead_ratio), :>, 0.0
    assert_equal %i[plain cst], report.fetch(:measurements).keys
    assert_equal 2, report.fetch(:normal_samples).length
    assert_equal %i[plain legacy_cst red_green_cst], recovery.fetch(:measurements).keys
    assert_operator recovery.fetch(:legacy_cst_overhead_ratio), :>, 0.0
    assert_operator recovery.fetch(:red_green_cst_overhead_ratio), :>, 0.0
    assert_operator report.dig(:green_identity, :occurrences), :>, 0
    assert_operator report.dig(:green_identity, :identity_reuse_ratio), :>=, 0.0
    assert_operator report.dig(:construction_probe, :legacy_cst, :node_and_token_constructions), :>, 0
    assert_operator report.dig(:construction_probe, :red_green_cst, :node_and_token_constructions), :>, 0
  end

  def test_options_reject_non_positive_workloads
    assert_raises(OptionParser::InvalidArgument) { CSTBenchmark.parse_options(["--rules", "0"]) }
    assert_raises(OptionParser::InvalidArgument) { CSTBenchmark.parse_options(["--iterations", "0"]) }
    assert_raises(OptionParser::InvalidArgument) { CSTBenchmark.parse_options(["--runs", "0"]) }
  end
end
