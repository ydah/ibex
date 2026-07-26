# frozen_string_literal: true

require_relative "test_helper"

class LocationTest < Minitest::Test
  def test_is_immutable_and_joins_text_and_byte_ranges
    first = Ibex::Location.new(
      file: "source.rb", line: 2, column: 3, end_column: 5,
      start_byte: 10, end_byte: 12, source_line: "α + β"
    )
    last = Ibex::Location.new(
      file: "source.rb", line: 4, column: 1, end_line: 4, end_column: 2,
      start_byte: 30, end_byte: 31
    )

    joined = first.join(last)

    assert_predicate first, :frozen?
    assert_equal [2, 3, 4, 2], [joined.line, joined.column, joined.end_line, joined.end_column]
    assert_equal [10, 31], [joined.start_byte, joined.end_byte]
    assert_equal "α + β", joined.source_line
    assert_equal joined.to_h, Ibex::Location.join([last, first]).to_h
  end

  def test_validates_ranges_and_files
    assert_raises(ArgumentError) { Ibex::Location.new(line: 0, column: 1) }
    assert_raises(ArgumentError) { Ibex::Location.new(line: 2, column: 2, end_line: 1) }
    assert_raises(ArgumentError) { Ibex::Location.join([]) }

    first = Ibex::Location.new(file: "one", line: 1, column: 1)
    second = Ibex::Location.new(file: "two", line: 1, column: 1)
    assert_raises(ArgumentError) { first.join(second) }
  end
end
