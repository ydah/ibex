# frozen_string_literal: true

require_relative "parser_test"
require "json"
require "stringio"

class RuntimeJSONLTracerTest < Minitest::Test
  def test_records_shift_and_reduce_events_as_json_lines
    output = StringIO.new
    parser = RuntimeParserTest::Calculator.new([[:INT, 1], ["+", nil], [:INT, 2]])

    assert_same parser, Ibex::Runtime::JSONLTracer.attach(parser, io: output)
    assert_equal 3, parser.do_parse

    events = output.string.lines.map { |line| JSON.parse(line) }
    assert_equal "shift", events.first.fetch("event")
    assert_equal "INT", events.first.fetch("token")
    assert_equal "1", events.first.fetch("value")
    assert_equal 3, events.first.fetch("state")
    assert_includes events.map { |event| event["event"] }, "reduce"
    assert_equal 0, events.last.fetch("production_id")
    assert_equal "3", events.last.fetch("result")
  end

  def test_preserves_existing_hooks
    output = StringIO.new
    parser = RuntimeParserTest::Calculator.new([[:INT, 5]])
    shifts = []
    parser.define_singleton_method(:on_shift) { |*payload| shifts << payload }

    Ibex::Runtime::JSONLTracer.attach(parser, io: output)
    assert_equal 5, parser.do_parse
    assert_equal [[2, 5, 3]], shifts
    shift_count = output.string.lines.count { |line| JSON.parse(line)["event"] == "shift" }
    assert_equal 1, shift_count
  end

  def test_records_successful_error_recovery
    output = StringIO.new
    parser = RuntimeParserTest::RecoveringStatements.new([[:BAD, "bad"], [";", nil]])
    Ibex::Runtime::JSONLTracer.attach(parser, io: output)

    assert_equal [:error], parser.do_parse
    recovery = output.string.lines.map { |line| JSON.parse(line) }.find { |event| event["event"] == "error_recover" }
    assert_equal ":BAD", recovery.fetch("token")
    assert_equal '"bad"', recovery.fetch("value")
  end

  def test_trace_failures_do_not_change_the_parse_or_application_hooks
    broken_value = Object.new
    broken_value.define_singleton_method(:inspect) { raise "inspect failed" }
    output = Object.new
    output.define_singleton_method(:puts) { |_line| raise IOError, "closed" }
    parser = RuntimeParserTest::Calculator.new([[:INT, broken_value]])
    shifts = []
    parser.define_singleton_method(:on_shift) { |*payload| shifts << payload }
    Ibex::Runtime::JSONLTracer.attach(parser, io: output)

    assert_same broken_value, parser.do_parse
    assert_equal 1, shifts.length
  end

  def test_trace_handles_values_without_inspect_or_class
    value = BasicObject.new
    output = StringIO.new
    parser = RuntimeParserTest::Calculator.new([[:INT, value]])
    Ibex::Runtime::JSONLTracer.attach(parser, io: output)

    assert parser.do_parse.equal?(value)
    assert_includes output.string, "<inspect failed>"
  end

  def test_reattach_switches_output_without_duplicating_hooks
    first = StringIO.new
    second = StringIO.new
    parser = RuntimeParserTest::Calculator.new([[:INT, 8]])
    Ibex::Runtime::JSONLTracer.attach(parser, io: first)
    Ibex::Runtime::JSONLTracer.attach(parser, io: second)

    assert_equal 8, parser.do_parse
    assert_empty first.string
    assert_equal 3, second.string.lines.length
  end
end
