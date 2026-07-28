# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/cst"

class CSTBenchmarkTest < Minitest::Test
  def test_report_includes_normal_recovery_and_identity_measurements
    report = CSTBenchmark.benchmark(rules: 2, iterations: 1, runs: 2, seed: 12_345, output: nil)
    recovery = report.fetch(:recovery)

    assert_equal 5, report.fetch(:version)
    assert_operator report.fetch(:cst_overhead_ratio), :>, 0.0
    assert_equal %i[plain cst], report.fetch(:measurements).keys
    assert_equal 2, report.fetch(:normal_samples).length
    assert_equal %i[plain red_green_cst], recovery.fetch(:measurements).keys
    assert_operator recovery.fetch(:red_green_cst_overhead_ratio), :>, 0.0
    assert_operator report.dig(:green_identity, :occurrences), :>, 0
    assert_operator report.dig(:green_identity, :identity_reuse_ratio), :>=, 0.0
    constructions = report.dig(:construction_probe, :red_green_cst, :node_and_token_constructions)
    assert(constructions.nil? || constructions.positive?)
  end

  def test_options_reject_non_positive_workloads
    assert_raises(OptionParser::InvalidArgument) { CSTBenchmark.parse_options(["--rules", "0"]) }
    assert_raises(OptionParser::InvalidArgument) { CSTBenchmark.parse_options(["--iterations", "0"]) }
    assert_raises(OptionParser::InvalidArgument) { CSTBenchmark.parse_options(["--runs", "0"]) }
  end

  def test_measurements_tolerate_a_runtime_without_an_allocation_counter
    parser_class = Class.new do
      def parse(input) = input
    end

    GC.stub(:stat, {}) do
      measurement = CSTBenchmark.measure(parser_class, "input", 1)
      measurements, samples = CSTBenchmark.measure_normal(parser_class, parser_class, "input", 1, 2)

      assert_nil measurement.fetch(:allocated_objects)
      assert_nil measurements.dig(:plain, :allocated_objects)
      assert_nil measurements.dig(:cst, :allocated_objects)
      assert(samples.all? { |sample| sample.dig(:plain, :allocated_objects).nil? })
      assert(samples.all? { |sample| sample.dig(:cst, :allocated_objects).nil? })
    end
  end

  def test_construction_probe_marks_an_unsupported_tracepoint_as_unavailable
    unsupported_tracepoint = lambda do |*|
      raise ArgumentError, "unknown event: call"
    end

    TracePoint.stub(:new, unsupported_tracepoint) do
      result = CSTConstructionProbe.construction_counts(Object, "input")

      assert_nil result.fetch(:nodes)
      assert_nil result.fetch(:tokens)
      assert_nil result.fetch(:node_and_token_constructions)
    end
  end

  def test_construction_probe_marks_an_empty_trace_as_unavailable
    result = CSTConstructionProbe.measured_counts(nodes: 0, tokens: 0)

    assert_nil result.fetch(:nodes)
    assert_nil result.fetch(:tokens)
    assert_nil result.fetch(:node_and_token_constructions)
  end
end
