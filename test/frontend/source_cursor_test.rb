# frozen_string_literal: true

require_relative "../test_helper"

# rubocop:disable Metrics/ClassLength -- one cursor contract is easier to audit in one place.
class SourceCursorTest < Minitest::Test
  Cursor = Ibex::Frontend::SourceCursor
  private_constant :Cursor

  def test_ascii_positions_locations_and_span
    cursor = Cursor.new("ab\nc", "ascii.y")
    start = cursor.position

    assert_equal [0, 0, 1, 1], cursor_state(cursor)
    assert_equal({ file: "ascii.y", line: 1, column: 1 }, cursor.location.to_h)
    assert_equal 2, cursor.advance(2)
    assert_equal [2, 2, 1, 3], cursor_state(cursor)
    assert_equal 1, cursor.advance
    assert_equal [3, 3, 2, 1], cursor_state(cursor)
    assert_equal(
      {
        file: "ascii.y",
        start: { byte_offset: 0, line: 1, column: 1 },
        end: { byte_offset: 3, line: 2, column: 1 }
      },
      cursor.span_from(start).to_h
    )
  end

  def test_bmp_and_supplementary_characters_keep_character_and_byte_indices_distinct
    cursor = Cursor.new("é日😀x", "unicode.y")

    assert_equal "é", cursor.peek
    assert_equal 1, cursor.advance
    assert_equal [1, 2, 1, 2], cursor_state(cursor)
    assert_equal "日", cursor.peek
    assert_equal 2, cursor.advance(2)
    assert_equal [3, 9, 1, 4], cursor_state(cursor)
    assert_equal "x", cursor.peek
    assert_equal "x", cursor.rest
  end

  def test_crlf_and_cr_only_increment_lines_only_for_lf
    cursor = Cursor.new("a\r\nb\rc\n", "newlines.y")

    [1, 1, 1, 1, 1, 1, 1].each { |count| cursor.advance(count) }
    assert_equal [7, 7, 3, 1], cursor_state(cursor)

    cursor = Cursor.new("a\r\nb\rc\n", "newlines.y")
    expected = [
      [0, 0, 1, 1],
      [1, 1, 1, 2],
      [2, 2, 1, 3],
      [3, 3, 2, 1],
      [4, 4, 2, 2],
      [5, 5, 2, 3],
      [6, 6, 2, 4],
      [7, 7, 3, 1]
    ]
    states = [cursor_state(cursor)] + Array.new(7) do
      cursor.advance
      cursor_state(cursor)
    end
    assert_equal expected, states
  end

  def test_peek_preserves_absolute_negative_indexing
    cursor = Cursor.new("aé😀z", "peek.y")
    cursor.advance(2)

    assert_equal "😀", cursor.peek
    assert_equal "é", cursor.peek(-1)
    assert_equal "a", cursor.peek(-2)
    assert_equal "z", cursor.peek(-3)
    assert_equal "😀", cursor.peek(-4)
    assert_equal "é", cursor.peek(-5)
    assert_equal "a", cursor.peek(-6)
    assert_nil cursor.peek(-7)
    assert_equal "z", cursor.peek(1)
    assert_nil cursor.peek(2)
  end

  def test_peek_and_rest_return_fresh_mutable_utf8_strings
    cursor = Cursor.new("é😀", "strings.y")

    first = cursor.peek
    second = cursor.peek
    rest = cursor.rest
    other_rest = cursor.rest

    refute_same first, second
    refute_same rest, other_rest
    [first, second, rest, other_rest].each do |value|
      assert_equal Encoding::UTF_8, value.encoding
      refute_predicate value, :frozen?
    end
    first.replace("x")
    rest.replace("y")
    assert_equal "é", cursor.peek
    assert_equal "é😀", cursor.rest
  end

  def test_empty_and_eof_results_are_fresh_mutable_utf8_strings
    cursor = Cursor.new("", "empty.y")

    assert_predicate cursor, :eof?
    assert_nil cursor.peek
    first = cursor.rest
    second = cursor.rest
    assert_equal ["", ""], [first, second]
    refute_same first, second
    [first, second].each do |value|
      assert_equal Encoding::UTF_8, value.encoding
      refute_predicate value, :frozen?
    end
    first << "changed"
    assert_equal "", cursor.rest

    cursor = Cursor.new("x", "eof.y")
    assert_equal 1, cursor.advance
    assert_predicate cursor, :eof?
    assert_nil cursor.peek
    refute_same cursor.rest, cursor.rest
  end

  def test_advance_preserves_return_values_and_eof_overshoot
    cursor = Cursor.new("ab", "advance.y")

    assert_equal 0, cursor.advance(0)
    assert_equal(-2, cursor.advance(-2))
    assert_equal [0, 0, 1, 1], cursor_state(cursor)
    assert_equal 2, cursor.advance(2)
    assert_equal [2, 2, 1, 3], cursor_state(cursor)
    assert_nil cursor.advance
    assert_equal [2, 2, 1, 3], cursor_state(cursor)

    cursor = Cursor.new("😀", "advance.y")
    assert_nil cursor.advance(2)
    assert_equal [1, 4, 1, 2], cursor_state(cursor)
  end

  def test_advance_preserves_non_integer_failures
    cursor = Cursor.new("a", "count.y")

    [1.0, "1", nil].each do |count|
      assert_raises(NoMethodError) { cursor.advance(count) }
      assert_equal [0, 0, 1, 1], cursor_state(cursor)
    end
  end

  def test_advance_preserves_custom_times_return_and_partial_state
    count = Object.new
    def count.times
      yield
      yield
      :completed
    end

    cursor = Cursor.new("éx", "count.y")
    assert_equal :completed, cursor.advance(count)
    assert_equal [2, 3, 1, 3], cursor_state(cursor)

    cursor = Cursor.new("é", "count.y")
    assert_nil cursor.advance(count)
    assert_equal [1, 2, 1, 2], cursor_state(cursor)
  end

  def test_source_and_file_are_copied_frozen_and_detached
    string_class = Class.new(String)
    source = string_class.new("é")
    file = string_class.new("input.y")
    cursor = Cursor.new(source, file)
    source.replace("changed")
    file.replace("changed.y")

    assert_equal "é", cursor.source
    assert_equal "input.y", cursor.file
    assert_equal [string_class, string_class], [cursor.source.class, cursor.file.class]
    assert_instance_of String, cursor.peek
    assert_instance_of String, cursor.rest
    [cursor.source, cursor.file].each { |value| assert_predicate value, :frozen? }

    frozen_source = String.new("x").freeze
    frozen_cursor = Cursor.new(frozen_source, String.new("frozen.y").freeze)
    refute_same frozen_source, frozen_cursor.source
    assert_predicate frozen_cursor.source, :frozen?
  end

  def test_non_ascii_cursor_keeps_constant_size_auxiliary_state
    cursor = Cursor.new("#{'a' * (1024 * 1024)}é", "large.y")
    retained_collections = cursor.instance_variables.filter_map do |name|
      value = cursor.instance_variable_get(name)
      [name, value] if value.is_a?(Array) || value.is_a?(Hash)
    end

    refute_includes cursor.instance_variables, :@character_offsets
    assert_empty retained_collections
  end

  def test_invalid_utf8_is_rejected_before_cursor_initialization
    error = assert_raises(Ibex::Error) { Cursor.new("\xFF".b, "invalid.y") }

    assert_equal "invalid.y: input must be valid UTF-8", error.message
  end

  def test_random_operation_sequences_match_character_indexing
    random = Random.new(86_086)
    alphabet = ["a", "Z", "0", " ", "\0", "\r", "\n", "é", "日", "😀", "\u0301"]

    100.times do
      source = Array.new(random.rand(0..40)) { alphabet.sample(random: random) }.join
      assert_random_sequence(source, random)
    end
  end

  def test_random_large_offsets_and_cursor_positions_match_character_indexing
    random = Random.new(86_087)
    alphabet = ["a", "b", "\r", "\n", "é", "日", "😀", "\u0301"]
    source = Array.new(2048) { alphabet.sample(random: random) }.join
    cursor = Cursor.new(source, "large-random.y")
    expected = { index: 0, byte_offset: 0, line: 1, column: 1 }

    200.times do
      assert_random_advance(cursor, source, expected, random, maximum: 40)
      offsets = [
        random.rand(-10_000..10_000),
        -source.length - random.rand(1..10_000),
        source.length + random.rand(1..10_000),
        -expected[:index] - random.rand(0..source.length),
        random.rand(-4..4)
      ]
      offsets.each do |offset|
        message = [expected, offset].inspect
        assert_cursor_value(source[expected[:index] + offset], cursor.peek(offset), message)
      end
      assert_random_position(cursor, source, expected)
    end
  end

  private

  def assert_random_sequence(source, random)
    cursor = Cursor.new(source, "random.y")
    expected = { index: 0, byte_offset: 0, line: 1, column: 1 }

    100.times do
      case random.rand(4)
      when 0 then assert_random_peek(cursor, source, expected, random)
      when 1 then assert_equal(source[expected[:index]..] || "", cursor.rest, [source, expected].inspect)
      when 2 then assert_random_advance(cursor, source, expected, random)
      when 3 then assert_random_position(cursor, source, expected)
      end
    end
  end

  def assert_random_peek(cursor, source, expected, random)
    offset = random.rand(-(source.length + 5)..(source.length + 5))
    message = [source, expected, offset].inspect

    assert_cursor_value(source[expected[:index] + offset], cursor.peek(offset), message)
  end

  def assert_random_advance(cursor, source, expected, random, maximum: 6)
    count = random.rand(-2..maximum)
    expected_return = count.times do
      character = source[expected[:index]]
      break unless character

      advance_expected_cursor(expected, character)
    end
    assert_cursor_value(expected_return, cursor.advance(count), [source, expected, count].inspect)
  end

  def advance_expected_cursor(expected, character)
    expected[:index] += 1
    expected[:byte_offset] += character.bytesize
    if character == "\n"
      expected[:line] += 1
      expected[:column] = 1
    else
      expected[:column] += 1
    end
  end

  def assert_random_position(cursor, source, expected)
    message = [source, expected].inspect
    assert_equal expected.values, cursor_state(cursor), message
    assert_equal expected.slice(:byte_offset, :line, :column), cursor.position.to_h, message
  end

  def assert_cursor_value(expected, actual, message)
    return assert_nil(actual, message) if expected.nil?

    assert_equal expected, actual, message
  end

  def cursor_state(cursor)
    [cursor.index, cursor.byte_offset, cursor.line, cursor.column]
  end
end
# rubocop:enable Metrics/ClassLength
