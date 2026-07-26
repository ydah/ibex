# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tool/error_ux_snapshot"

class ErrorUXSnapshotTest < Minitest::Test
  def test_json_error_comparison_and_repair_measurement_are_current
    command = ENV.fetch("RACC", "racc")
    skip "racc executable is unavailable" unless
      system(command, "--version", out: File::NULL, err: File::NULL)

    assert ErrorUXSnapshot.verify?
  end
end
