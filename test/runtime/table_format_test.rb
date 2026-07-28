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

  class VersionOneParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(format_version: 1).freeze

    def self.parser_tables = TABLES
  end

  class VersionTwoParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(format_version: 2).freeze

    def self.parser_tables = TABLES
  end

  class VersionThreeParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(format_version: 3).freeze

    def self.parser_tables = TABLES
  end

  class VersionFourParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(format_version: 4).freeze

    def self.parser_tables = TABLES
  end

  class VersionFiveParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(format_version: 5).freeze

    def self.parser_tables = TABLES
  end

  class LegacyCSTParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(cst: true).freeze

    def self.parser_tables = TABLES
    def next_token = raise("legacy CST parser read a token")
  end

  class FutureParser < CurrentParser
    TABLES = CurrentParser::TABLES.merge(
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION + 1
    ).freeze

    def self.parser_tables = TABLES
    def next_token = raise("future parser read a token")
  end

  class CachedValidationParser < CurrentParser
    TABLES = TestRuntimeCapabilities.make_shareable(
      CurrentParser::TABLES.merge(
        productions: [
          { lhs: 2, length: 0, action: :_ibex_action_0, values_action: true } # rubocop:disable Naming/VariableNumber
        ]
      )
    )

    class << self
      attr_accessor :validation_calls

      def parser_tables = TABLES
    end

    private

    def validate_generated_action_contracts!(...)
      self.class.validation_calls = self.class.validation_calls.to_i + 1
      super
    end
  end

  class MutableValidationParser < CachedValidationParser
    TABLES = CurrentParser::TABLES.merge(
      productions: [
        { lhs: 2, length: 0, action: :_ibex_action_0, values_action: true } # rubocop:disable Naming/VariableNumber
      ]
    )

    def self.parser_tables = TABLES
  end

  def test_current_hand_written_table_is_accepted
    assert_equal 6, Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION
    assert_equal [1, 2, 3, 4, 5, 6], Ibex::Runtime::SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS
    assert_nil CurrentParser.new.do_parse
  end

  def test_version_one_through_five_tables_remain_accepted
    assert_nil VersionOneParser.new.do_parse
    assert_nil VersionTwoParser.new.do_parse
    assert_nil VersionThreeParser.new.do_parse
    assert_nil VersionFourParser.new.do_parse
    assert_nil VersionFiveParser.new.do_parse
  end

  def test_legacy_cst_tables_fail_before_reading_tokens
    error = assert_raises(Ibex::Runtime::ParseError) { LegacyCSTParser.new.do_parse }

    assert_match(/\(tables\):1:1:/, error.message)
    assert_match(/legacy CST parser tables are unsupported/, error.message)
    assert_match(/regenerate/i, error.message)
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
    assert_match(/unsupported parser table format version 7/, error.message)
    assert_match(/runtime supports 1, 2, 3, 4, 5, 6/, error.message)
    assert_match(/regenerate/i, error.message)
  end

  def test_deeply_frozen_generated_action_contracts_are_cached_per_class
    skip "Ractor shareability is unavailable" if
      TestRuntimeCapabilities.ractor_shareable?(CachedValidationParser::TABLES).nil?

    CachedValidationParser.validation_calls = 0
    CachedValidationParser.remove_instance_variable(:@__ibex_validated_parser_tables) if
      CachedValidationParser.instance_variable_defined?(:@__ibex_validated_parser_tables)

    2.times { assert_nil CachedValidationParser.new.do_parse }

    assert_equal 1, CachedValidationParser.validation_calls
  end

  def test_mutable_action_contracts_are_revalidated
    MutableValidationParser.validation_calls = 0

    assert_nil MutableValidationParser.new.do_parse
    MutableValidationParser::TABLES.fetch(:productions).first[:values_action] = false
    assert_nil MutableValidationParser.new.do_parse

    assert_equal 2, MutableValidationParser.validation_calls
  ensure
    MutableValidationParser::TABLES.fetch(:productions).first[:values_action] = true
  end
end
