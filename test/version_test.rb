# frozen_string_literal: true

require_relative "test_helper"

class VersionTest < Minitest::Test
  def test_has_a_version
    refute_nil Ibex::VERSION
  end
end
