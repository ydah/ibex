# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class ImpactBaselineTest < Minitest::Test
  def test_missing_baseline_is_empty_and_write_is_sorted
    Dir.mktmpdir("ibex-impact-baseline") do |directory|
      path = File.join(directory, "baseline.json")
      baseline = Ibex::Impact::Baseline.new(path)

      assert_empty baseline.conflicts
      baseline.write(%w[zeta alpha alpha])

      assert_equal %w[alpha zeta], baseline.conflicts
    end
  end
end
