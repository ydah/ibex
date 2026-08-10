# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require_relative "../../tool/quality/direct_ielr_regression"

class DirectIELRRegressionTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  FIG1 = File.join(ROOT, "test/fixtures/ielr/fig1.y")

  def test_bounded_probe_targets_direct_strategy_and_keeps_decision_no_go
    result = Ibex::Quality::DirectIELRRegression.new(
      root: ROOT, count: 2, wall_seconds: 2, paths: [FIG1], output: StringIO.new
    ).verify!

    strategies = result.fetch(:benchmark).fetch("workloads").map { |workload| workload.fetch("strategy") }.sort
    assert_equal %w[direct partition], strategies
    assert(result.fetch(:fuzz).all? { |report| report.fetch(:ielr_strategy) == "direct" })
  end
end
