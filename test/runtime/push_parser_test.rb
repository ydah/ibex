# frozen_string_literal: true

require_relative "parser_test"

class RuntimePushParserTest < Minitest::Test
  def test_caller_driven_push_and_finish
    parser = RuntimeParserTest::Calculator.new([])

    assert_equal :need_more, parser.push(:INT, 1)
    assert_equal :need_more, parser.push("+", nil)
    assert_equal :need_more, parser.push(:INT, 2)
    assert_equal 3, parser.finish
  end

  def test_push_session_rejects_input_after_finish_until_reset
    parser = RuntimeParserTest::Calculator.new([])
    parser.push(:INT, 4)
    assert_equal 4, parser.finish

    error = assert_raises(Ibex::ParseError) { parser.push(:INT, 5) }
    assert_match(/push session is finished/, error.message)

    parser.reset_push
    parser.push(:INT, 5)
    assert_equal 5, parser.finish
  end

  def test_push_reports_early_acceptance_and_recovery_needs_more_input
    accepting = RuntimeParserTest::AcceptingCalculator.new([])
    assert_equal :need_more, accepting.push(:INT, 7)
    assert_equal [:accepted, 7], accepting.push("+", nil)

    recovering = RuntimeParserTest::RecoveringStatements.new([])
    assert_equal :need_more, recovering.push(:BAD, :bad)
    assert_equal [":BAD"], recovering.errors
  end

  def test_push_distinguishes_unrecoverable_termination_from_acceptance
    parser = RuntimeParserTest::Calculator.new([])
    parser.define_singleton_method(:on_error) { |_token_id, _value, _stack| nil }

    assert_equal [:rejected, nil], parser.push("+", nil)
  end

  def test_parser_drivers_reject_reentrant_push_without_corrupting_state
    pull = RuntimeParserTest::Calculator.new([[:INT, 1]])
    pull.define_singleton_method(:on_shift) { |*| push(:INT, 2) }
    error = assert_raises(Ibex::ParseError) { pull.do_parse }
    assert_match(/parser driver is already running/, error.message)

    pushed = RuntimeParserTest::Calculator.new([])
    pushed.define_singleton_method(:on_shift) do |*|
      reset_push
      push(:INT, 2)
    end
    error = assert_raises(Ibex::ParseError) { pushed.push(:INT, 1) }
    assert_match(/parser driver is already running/, error.message)
  end

  def test_debug_output_cannot_reenter_while_a_push_session_starts
    parser = RuntimeParserTest::Calculator.new([])
    sink = Object.new
    sink.define_singleton_method(:puts) { |_message| parser.push(:INT, 99) }
    parser.yydebug = true
    parser.yydebug_output = sink

    error = assert_raises(Ibex::ParseError) { parser.push(:INT, 1) }
    assert_match(/parser driver is already running/, error.message)

    parser.yydebug = false
    parser.reset_push
    parser.push(:INT, 1)
    assert_equal 1, parser.finish
  end

  def test_push_lifecycle_errors_are_positioned
    parser = RuntimeParserTest::Calculator.new([])
    parser.push(:INT, 1)

    error = assert_raises(Ibex::ParseError) { parser.do_parse }
    assert_match(/\(input\):1:1:.*active push session/, error.message)

    parser.reset_push
    error = assert_raises(Ibex::ParseError) { parser.push(nil) }
    assert_match(/\(input\):1:1:.*call finish for EOF/, error.message)

    parser.push(:INT, 2)
    assert_equal 2, parser.finish
    error = assert_raises(Ibex::ParseError) { parser.finish }
    assert_match(/\(input\):1:1:.*push session is finished/, error.message)
  end
end
