# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/golden"
require "stringio"

class GoldenTest < Minitest::Test
  def test_committed_generated_sources_match_and_are_reproducible
    golden = Ibex::Quality::Golden.new(output: StringIO.new)

    assert_equal 3, golden.verify!
    assert_equal 3, golden.reproducible!
  end
end
