# frozen_string_literal: true

require_relative "../test_helper"

class RuntimeTableFormatTest < Minitest::Test
  class CurrentParser < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: {},
      token_names: { 0 => "$eof", 1 => "error" },
      actions: [{ 0 => [:accept] }],
      gotos: [{}],
      productions: []
    }.freeze

    def self.parser_tables = TABLES
    def next_token = nil
  end

  class LegacyParser < CurrentParser
    TABLES = CurrentParser::TABLES.except(:format_version).freeze

    def self.parser_tables = TABLES
    def next_token = raise("legacy parser read a token")
  end

  class FutureParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION + 1
    ).freeze

    def self.parser_tables = TABLES
    def next_token = raise("future parser read a token")
  end

  def test_current_hand_written_table_is_accepted
    assert_equal 1, Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION
    assert_nil CurrentParser.new.do_parse
  end

  def test_missing_parser_table_format_version_fails_before_reading_tokens
    error = assert_raises(Ibex::Runtime::ParseError) { LegacyParser.new.do_parse }

    assert_match(/\(tables\):1:1:/, error.message)
    assert_match(/missing :format_version/, error.message)
    assert_match(/regenerate/i, error.message)
  end

  def test_unsupported_parser_table_format_version_fails_before_reading_tokens
    error = assert_raises(Ibex::Runtime::ParseError) { FutureParser.new.do_parse }

    assert_match(/\(tables\):1:1:/, error.message)
    assert_match(/unsupported parser table format version 2/, error.message)
    assert_match(/runtime supports 1/, error.message)
    assert_match(/regenerate/i, error.message)
  end
end
