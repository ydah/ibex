# frozen_string_literal: true

require_relative "parser_test"

class RuntimeParseErrorTest < Minitest::Test
  LOCATION = {
    file: "input.expr",
    line: 4,
    column: 5,
    source_line: "sum IN value"
  }.freeze

  def test_default_error_exposes_structured_context_and_caret
    error = assert_raises(Ibex::ParseError) do
      RuntimeParserTest::Calculator.new([[:IN, "payload", LOCATION]]).do_parse
    end

    assert_equal "input.expr:4:5", error.location_label
    assert_equal LOCATION, error.location
    assert_equal "payload", error.token_value
    assert_equal ":IN", error.token_name
    assert_equal %w[INT (], error.expected_tokens
    assert_equal ["INT"], error.suggestions
    assert_equal 0, error.state
    assert_match(/sum IN value\n    \^/, error.message)
    assert_match(/did you mean INT\?/, error.message)
  end

  def test_push_accepts_the_same_optional_location_contract
    parser = RuntimeParserTest::Calculator.new([])

    error = assert_raises(Ibex::ParseError) { parser.push(:IN, "payload", LOCATION) }

    assert_equal LOCATION, error.location
    assert_equal ["INT"], error.suggestions
  end

  def test_finish_accepts_an_eof_location
    parser = RuntimeParserTest::Calculator.new([])
    parser.push("(", nil)

    error = assert_raises(Ibex::ParseError) { parser.finish(location: LOCATION) }
    assert_equal LOCATION, error.location
    assert_equal "$eof", error.token_name
  end

  def test_pull_accepts_a_located_eof_tuple
    parser = RuntimeParserTest::Calculator.new([["(", nil], [nil, nil, LOCATION]])

    error = assert_raises(Ibex::ParseError) { parser.do_parse }
    assert_equal LOCATION, error.location
  end

  def test_location_objects_prefer_named_readers_over_unrelated_indexing
    location_class = Struct.new(:file, :line, :column, :source_line) do
      def [](_key)
        raise TypeError, "not a keyed location"
      end
    end
    location = location_class.new("object.expr", 2, 3, "x IN")

    error = assert_raises(Ibex::ParseError) do
      RuntimeParserTest::Calculator.new([[:IN, nil, location]]).do_parse
    end

    assert_equal "object.expr:2:3", error.location_label
    assert_match(/x IN\n  \^/, error.message)
  end

  def test_string_keyed_hash_locations_are_supported
    location = { "file" => "string.expr", "line" => 8, "column" => 2 }
    error = assert_raises(Ibex::ParseError) do
      RuntimeParserTest::Calculator.new([[:IN, nil, location]]).do_parse
    end

    assert_equal "string.expr:8:2", error.location_label
  end

  def test_plain_parse_error_construction_remains_compatible
    error = Ibex::ParseError.new("plain failure")

    assert_equal "plain failure", error.message
    assert_nil error.location
    assert_empty error.expected_tokens
    assert_empty error.suggestions
  end

  def test_structured_collections_are_immutable_copies
    expected = ["INT"]
    suggestions = ["ID"]
    error = Ibex::ParseError.new(expected_tokens: expected, suggestions: suggestions)
    expected << "OTHER"
    suggestions.clear

    assert_equal ["INT"], error.expected_tokens
    assert_equal ["ID"], error.suggestions
    assert_predicate error.expected_tokens, :frozen?
    assert_predicate error.suggestions, :frozen?
  end
end
