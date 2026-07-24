# frozen_string_literal: true

require_relative "../test_helper"

class RuntimeLocationSpanTest < Minitest::Test
  def test_nonempty_reduction_flattens_nested_boundaries
    first = { file: "input.txt", line: 1, column: 2 }
    middle = { file: "input.txt", line: 1, column: 4 }
    last = { file: "input.txt", line: 2, column: 3, end_line: 2, end_column: 6 }
    nested = Ibex::Runtime::LocationSpan.new(start: first, finish: middle)

    span = Ibex::Runtime::LocationSpan.for_reduction([nested, nil, last], lookahead: nil)

    assert_same first, span.start
    assert_same last, span.finish
    assert_equal "input.txt", span.file
    assert_equal 1, span.line
    assert_equal 2, span.column
    assert_equal 2, span.end_line
    assert_equal 6, span.end_column
    refute span.empty?
    assert_predicate span, :frozen?
  end

  def test_empty_reduction_is_zero_width_at_lookahead
    lookahead = {
      "file" => "input.txt", "line" => 4, "column" => 7,
      "end_file" => "input.txt", "end_line" => 6, "end_column" => 20
    }

    span = Ibex::Runtime::LocationSpan.for_reduction([], lookahead: lookahead)

    assert_same lookahead, span.start
    assert_same lookahead, span.finish
    assert span.empty?
    assert_equal "input.txt", span.end_file
    assert_equal 4, span.end_line
    assert_equal 7, span.end_column
  end

  def test_empty_reduction_uses_the_start_of_a_span_lookahead
    start = { file: "input.txt", line: 2, column: 3, end_line: 2, end_column: 8 }
    finish = { file: "input.txt", line: 5, column: 9 }
    lookahead = Ibex::Runtime::LocationSpan.new(start: start, finish: finish)

    span = Ibex::Runtime::LocationSpan.for_reduction([], lookahead: lookahead)

    assert_same start, span.start
    assert_same start, span.finish
    assert span.empty?
    assert_equal 2, span.end_line
    assert_equal 3, span.end_column
  end

  def test_reduction_without_any_location_remains_unlocated
    assert_nil Ibex::Runtime::LocationSpan.for_reduction([nil], lookahead: Object.new)
    assert_nil Ibex::Runtime::LocationSpan.for_reduction([], lookahead: nil)
  end
end
