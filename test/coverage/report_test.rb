# frozen_string_literal: true

require_relative "../runtime/parser_test"
require "json_schemer"
require "stringio"
require "tempfile"

class CoverageReportTest < Minitest::Test
  DIGEST = "sha256:#{'a' * 64}".freeze
  SCHEMA = JSONSchemer.schema(
    JSON.parse(File.read(File.expand_path("../../schema/runtime-coverage-v1.schema.json", __dir__)))
  )

  class CoveredCalculator < RuntimeParserTest::Calculator
    TABLES = RuntimeParserTest::Calculator::TABLES.merge(
      grammar_digest: DIGEST,
      state_count: 9,
      production_count: 4
    ).freeze

    def self.parser_tables = TABLES
  end

  def test_collects_complete_generated_parser_sessions_and_round_trips
    with_trace do |trace|
      report = Ibex::Coverage::Collector.collect_file(trace)

      assert_equal DIGEST, report.grammar_digest
      assert_equal 1, report.sessions
      assert_equal 5, report.event_count
      assert_equal({ 0 => 1, 1 => 1, 2 => 1, 3 => 1 }, report.state_hits)
      assert_equal({ 1 => 1, 2 => 1 }, report.production_hits)
      assert_empty SCHEMA.validate(report.to_h).to_a

      Tempfile.create(["coverage", ".json"]) do |file|
        file.write(report.to_json)
        file.flush
        assert_equal report.to_h, Ibex::Coverage::Report.load_file(file.path).to_h
      end
    end
  end

  def test_merge_sums_hits_and_rejects_different_parser_metadata
    with_trace do |trace|
      report = Ibex::Coverage::Collector.collect_file(trace)
      merged = Ibex::Coverage::Report.merge([report, report])

      assert_equal 2, merged.sessions
      assert_equal 10, merged.event_count
      assert_equal({ 0 => 2, 1 => 2, 2 => 2, 3 => 2 }, merged.state_hits)
      assert_equal({ 1 => 2, 2 => 2 }, merged.production_hits)

      different = Ibex::Coverage::Report.new(
        grammar_digest: "sha256:#{'b' * 64}",
        table_format_version: 3,
        state_count: 9,
        production_count: 4,
        sessions: 1,
        event_count: 1,
        state_hits: { 0 => 1 },
        production_hits: {}
      )
      error = assert_raises(ArgumentError) { Ibex::Coverage::Report.merge([report, different]) }
      assert_includes error.message, "grammar_digest"
    end
  end

  def test_recovery_destination_counts_as_a_state_hit
    documents = [
      event(1, "start", start_data),
      event(2, "error", {}),
      event(3, "recover", { "state" => 4 }),
      event(4, "reject", {})
    ]
    with_event_documents(documents) do |path|
      report = Ibex::Coverage::Collector.collect_file(path)
      assert_equal({ 0 => 1, 4 => 1 }, report.state_hits)
    end
  end

  def test_rejects_gaps_truncation_mixed_metadata_and_out_of_range_ids
    invalid_streams = [
      [event(1, "start", start_data), event(3, "accept", {})],
      [event(1, "start", start_data)],
      [
        event(1, "start", start_data),
        event(2, "accept", {}),
        event(1, "start", start_data.merge("grammar_digest" => "sha256:#{'b' * 64}")),
        event(2, "accept", {})
      ],
      [event(1, "start", start_data), event(2, "shift", { "state" => 9 }), event(3, "accept", {})]
    ]

    invalid_streams.each do |documents|
      with_event_documents(documents) do |path|
        assert_raises(Ibex::Error) { Ibex::Coverage::Collector.collect_file(path) }
      end
    end
  end

  def test_event_reader_bounds_lines_nesting_utf8_and_envelope_fields
    Tempfile.create(["events", ".jsonl"]) do |file|
      file.binmode
      file.write("x" * (Ibex::Coverage::EventStream::MAX_LINE_BYTES + 1))
      file.flush
      assert_raises(Ibex::Error) { Ibex::Coverage::Collector.collect_file(file.path) }
    end

    incomplete = event(1, "shift", {})
    incomplete.fetch("data").delete("value")
    invalid_lines = [
      "#{'[' * 33}0#{']' * 33}",
      "{\"bad\":\"\xFF\"}".b,
      JSON.generate(event(1, "start", start_data).merge("extra" => true)),
      JSON.generate(incomplete)
    ]
    invalid_lines.each do |line|
      Tempfile.create(["events", ".jsonl"]) do |file|
        file.binmode
        file.write(line)
        file.write("\n")
        file.flush
        assert_raises(Ibex::Error) { Ibex::Coverage::Collector.collect_file(file.path) }
      end
    end
  end

  def test_report_loader_rejects_unsorted_duplicate_hits_and_unknown_fields
    report = Ibex::Coverage::Report.new(
      grammar_digest: DIGEST,
      table_format_version: 3,
      state_count: 9,
      production_count: 4,
      sessions: 1,
      event_count: 2,
      state_hits: { 0 => 1, 2 => 1 },
      production_hits: {}
    ).to_h
    invalid = [
      report.merge("state_hits" => [{ "id" => 2, "count" => 1 }, { "id" => 0, "count" => 1 }]),
      report.merge("state_hits" => [{ "id" => 0, "count" => 1 }, { "id" => 0, "count" => 2 }]),
      report.merge("unknown" => true)
    ]

    invalid.each do |document|
      Tempfile.create(["coverage", ".json"]) do |file|
        file.write(JSON.generate(document))
        file.flush
        assert_raises(Ibex::Error) { Ibex::Coverage::Report.load_file(file.path) }
      end
    end
  end

  private

  def with_trace
    Tempfile.create(["events", ".jsonl"]) do |file|
      parser = CoveredCalculator.new([[:INT, 3]])
      Ibex::Runtime::EventJSONLTracer.attach(parser, io: file)
      assert_equal 3, parser.do_parse
      file.flush
      yield file.path
    end
  end

  def with_event_documents(documents)
    Tempfile.create(["events", ".jsonl"]) do |file|
      documents.each { |document| file.puts(JSON.generate(document)) }
      file.flush
      yield file.path
    end
  end

  def event(sequence, type, data)
    {
      "ibex_runtime_event" => "runtime-event",
      "schema_version" => 1,
      "sequence" => sequence,
      "event" => type,
      "data" => default_event_data(type).merge(data)
    }
  end

  def default_event_data(type)
    token = { "state" => 0, "token_id" => 2, "token" => "TOKEN", "value" => nil, "location" => nil }
    case type
    when "shift" then token.merge("from_state" => 0)
    when "reduce"
      {
        "production_id" => 0, "lhs" => 5, "rhs_length" => 1,
        "pre_state" => 1, "post_state" => 0, "goto_state" => 1,
        "result" => nil, "location" => nil
      }
    when "error" then token.merge("reason" => "syntax")
    when "recover" then token.merge("from_state" => 0, "reason" => "syntax")
    when "discard" then token.merge("reason" => "recovery")
    when "accept" then { "state" => 0, "result" => nil, "reason" => "table" }
    when "reject" then token.merge("reason" => "no_recovery_state")
    else {}
    end
  end

  def start_data
    {
      "driver" => "pull",
      "initial_state" => 0,
      "table_format_version" => 3,
      "grammar_digest" => DIGEST,
      "state_count" => 9,
      "production_count" => 4
    }
  end
end
