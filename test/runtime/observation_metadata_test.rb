# frozen_string_literal: true

require_relative "../test_helper"

class RuntimeObservationMetadataTest < Minitest::Test
  TABLES = {
    format_version: 1,
    tokens: {},
    token_names: { 0 => "$eof", 1 => "error" },
    actions: [{ 0 => [:accept] }],
    gotos: [{}],
    productions: []
  }.freeze

  def test_legacy_table_reports_format_and_nullable_generation_metadata
    parser_class = Class.new(Ibex::Runtime::Parser) do
      define_singleton_method(:parser_tables) { RuntimeObservationMetadataTest::TABLES }
      define_method(:next_token) { nil }
    end
    parser = parser_class.new
    events = []
    parser.observe { |event| events << event }

    assert_nil parser.do_parse
    assert_equal(
      {
        "driver" => "pull",
        "initial_state" => 0,
        "table_format_version" => 1,
        "grammar_digest" => nil,
        "state_count" => nil,
        "production_count" => nil
      },
      events.first.data
    )
  end

  def test_start_event_reuses_the_table_lookup_performed_by_validation
    parser_class = Class.new(Ibex::Runtime::Parser) do
      @table_calls = 0

      class << self
        attr_reader :table_calls

        def parser_tables
          @table_calls += 1
          RuntimeObservationMetadataTest::TABLES
        end
      end

      define_method(:next_token) { nil }
    end
    parser = parser_class.new
    parser.observe { |event| raise "stop after start" if event.type == :start }

    assert_raises(RuntimeError) { parser.do_parse }
    assert_equal 1, parser_class.table_calls
  end
end
