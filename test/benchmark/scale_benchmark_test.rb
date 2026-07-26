# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/scale"

class ScaleBenchmarkTest < Minitest::Test
  def test_generated_scale_report_is_deterministic_and_structured
    report = ScaleBenchmark.benchmark(rules: 20, iterations: 2, json: false)

    assert_equal "ibex_scale_benchmark", report.fetch(:artifact)
    assert_equal 1, report.fetch(:schema_version)
    assert_equal 21, report.dig(:structure, :productions)
    assert_operator report.dig(:structure, :final_states), :>, 20
    assert_equal 0, report.dig(:structure, :conflicts, :sr)
    assert_equal 0, report.dig(:structure, :conflicts, :rr)
    assert_operator report.dig(:structure, :generated_bytes), :>, 0
    assert_equal 64, report.dig(:digests, :automaton_ir_sha256).length
  end

  def test_options_require_positive_work
    assert_raises(OptionParser::InvalidArgument) { ScaleBenchmark.parse_options(["--rules", "0"]) }
    assert_raises(OptionParser::InvalidArgument) { ScaleBenchmark.parse_options(["--iterations", "0"]) }
  end
end
