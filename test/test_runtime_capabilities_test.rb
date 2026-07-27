# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeCapabilitiesTest < Minitest::Test
  def test_allocation_counter_requires_the_statistic
    GC.stub(:stat, {}) do
      refute TestRuntimeCapabilities.allocation_counter?
    end
  end

  def test_allocation_counter_requires_a_monotonic_value
    GC.stub(:stat, { total_allocated_objects: 0 }) do
      refute TestRuntimeCapabilities.allocation_counter?
    end
  end

  def test_allocation_counter_accepts_an_increasing_value
    readings = [10, 150]
    statistic = lambda do
      { total_allocated_objects: readings.shift }
    end

    GC.stub(:stat, statistic) do
      assert TestRuntimeCapabilities.allocation_counter?
    end
  end
end
