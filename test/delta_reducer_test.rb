# frozen_string_literal: true

require_relative "test_helper"

class DeltaReducerTest < Minitest::Test
  def test_minimizes_a_failure_without_reordering_items
    reducer = Ibex::DeltaReducer.new(max_trials: 100)
    result = reducer.minimize(%w[noise START middle END tail]) do |items|
      items.include?("START") && items.include?("END")
    end

    assert_equal %w[START END], result.items
    assert result.complete
    assert_operator result.trials, :<=, 100
    assert_equal 5, result.original_size
  end

  def test_returns_an_explicit_incomplete_result_at_the_trial_bound
    reducer = Ibex::DeltaReducer.new(max_trials: 2)
    result = reducer.minimize(%w[A B C D]) { |items| items.include?("A") }

    refute result.complete
    assert_equal 2, result.trials
  end

  def test_rejects_an_input_that_does_not_reproduce
    error = assert_raises(Ibex::Error) do
      Ibex::DeltaReducer.new(max_trials: 10).minimize(%w[A B]) { false }
    end

    assert_includes error.message, "does not reproduce"
  end
end
