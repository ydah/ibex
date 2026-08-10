# frozen_string_literal: true

require_relative "parser_test"
require "json"
require "json_schemer"
require "stringio"

class RuntimeEventJSONLTracerTest < Minitest::Test
  SCHEMA = JSONSchemer.schema(
    JSON.parse(File.read(File.expand_path("../../schema/runtime-event-v1.schema.json", __dir__)))
  )

  def test_emits_schema_valid_json_lines_and_detaches
    output = StringIO.new
    parser = RuntimeParserTest::Calculator.new([[:INT, 3]])
    tracer = Ibex::Runtime::EventJSONLTracer.attach(parser, io: output)

    assert_instance_of Ibex::Runtime::EventJSONLTracer, tracer
    assert_same parser, tracer.parser
    assert_equal 3, parser.do_parse

    documents = output.string.lines.map { |line| JSON.parse(line) }
    assert_equal(%w[start shift reduce reduce accept], documents.map { |event| event.fetch("event") })
    documents.each { |event| assert_empty SCHEMA.validate(event).to_a }

    assert tracer.detach
    refute tracer.detach
  end

  def test_output_failure_propagates_and_does_not_emit_reject
    output = Object.new
    output.define_singleton_method(:puts) { |_line| raise IOError, "closed" }
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    events = []
    parser.observe { |event| events << event.type }
    Ibex::Runtime::EventJSONLTracer.attach(parser, io: output)

    error = assert_raises(IOError) { parser.do_parse }

    assert_equal "closed", error.message
    assert_equal [:start], events
    refute_includes events, :reject
  end

  def test_recovery_and_rejection_documents_match_the_schema
    output = StringIO.new
    parser = RuntimeParserTest::RecoveringStatements.new([[:BAD, "bad"], [:BAD, "discard"], false])
    Ibex::Runtime::EventJSONLTracer.attach(parser, io: output)

    assert_nil parser.do_parse
    documents = output.string.lines.map { |line| JSON.parse(line) }
    assert_includes documents.map { |event| event.fetch("event") }, "error"
    assert_includes documents.map { |event| event.fetch("event") }, "recover"
    assert_includes documents.map { |event| event.fetch("event") }, "discard"
    assert_includes documents.map { |event| event.fetch("event") }, "reject"
    documents.each { |event| assert_empty SCHEMA.validate(event).to_a }
  end

  def test_schema_rejects_values_beyond_the_published_collection_and_string_caps
    document = {
      "ibex_runtime_event" => "runtime-event",
      "schema_version" => 1,
      "sequence" => 1,
      "event" => "accept",
      "data" => { "state" => 0, "result" => "x" * 257, "reason" => "table" }
    }

    refute SCHEMA.valid?(document)
    document["data"] = { "state" => 0, "result" => Array.new(18), "reason" => "table" }
    refute SCHEMA.valid?(document)
  end
end
