# frozen_string_literal: true

require_relative "parser_test"
require "stringio"

class RuntimeObservationEdgeTest < Minitest::Test
  def test_semantic_error_emits_reduce_error_and_recover
    parser = RuntimeParserTest::RecoveringStatements.new([[:INT, 1], [";", nil]])
    events = observe(parser)
    parser.define_singleton_method(:valid) do |_values, _stack|
      yyerror
      :semantic_error
    end

    assert_nil parser.do_parse
    semantic = events.filter_map.with_index { |event, index| index if event.type == :error }.first
    assert_equal :reduce, events.fetch(semantic - 1).type
    assert_equal "semantic", events.fetch(semantic).data.fetch("reason")
    assert_equal :recover, events.fetch(semantic + 1).type
  end

  def test_yyaccept_wins_over_yyerror_and_emits_one_terminal_event
    parser = RuntimeParserTest::AcceptingCalculator.new([[:INT, 7]])
    events = observe(parser)
    parser.define_singleton_method(:accept_term) do |values, _stack|
      yyerror
      yyaccept
      values.first
    end

    assert_equal 7, parser.do_parse
    assert_equal [:accept], events.select { |event| %i[accept reject].include?(event.type) }.map(&:type)
    refute_includes events.map(&:type), :error
  end

  def test_yyerrok_does_not_clear_a_new_semantic_error
    parser = RuntimeParserTest::RecoveringStatements.new([[:INT, 1], [";", nil]])
    events = observe(parser)
    parser.define_singleton_method(:valid) do |_values, _stack|
      yyerrok
      yyerror
      :semantic_error
    end

    assert_nil parser.do_parse
    assert_includes events.map(&:type), :error
    assert_includes events.map(&:type), :recover
  end

  def test_hook_observer_changes_apply_to_the_next_event
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    calls = []
    second = parser.observe { |event| calls << [:second, event.type] }
    parser.define_singleton_method(:on_shift) do |*|
      unobserve(second)
      observe { |event| calls << [:third, event.type] }
    end

    parser.do_parse

    assert_includes calls, %i[second shift]
    refute_includes calls, %i[third shift]
    assert_includes calls, %i[third reduce]
    refute_includes calls, %i[second reduce]
  end

  def test_first_observer_attached_in_reduce_hook_receives_semantic_accept
    parser = RuntimeParserTest::AcceptingCalculator.new([[:INT, 4]])
    events = []
    parser.define_singleton_method(:on_reduce) do |*|
      observe { |event| events << event } if events.empty?
    end

    assert_equal 4, parser.do_parse
    assert_equal [:accept], events.map(&:type)
    assert_equal 1, events.first.sequence
  end

  def test_observer_attached_in_on_error_starts_after_the_current_recovery_transaction
    parser = RuntimeParserTest::RecoveringStatements.new([[:BAD, "bad"], [";", nil]])
    events = []
    parser.define_singleton_method(:on_error) do |_token_id, _value, _stack|
      observe { |event| events << event }
    end

    assert_equal [:error], parser.do_parse
    refute_includes events.map(&:type), :error
    refute_includes events.map(&:type), :recover
    assert_equal :discard, events.first.type
    assert_equal 1, events.first.sequence

    reject_events = []
    unrecoverable = RuntimeParserTest::Calculator.new([["+", nil]])
    unrecoverable.define_singleton_method(:on_error) do |*|
      observe { |event| reject_events << event }
    end
    assert_nil unrecoverable.do_parse
    assert_empty reject_events
  end

  def test_reduce_hook_exception_suppresses_new_reduce
    parser = RuntimeParserTest::Calculator.new([[:INT, 1]])
    events = observe(parser)
    parser.define_singleton_method(:on_reduce) { |*| raise "reduce failed" }

    assert_raises(RuntimeError) { parser.do_parse }
    refute_includes events.map(&:type), :reduce
    refute_includes events.map(&:type), :reject
  end

  def test_recovery_hook_exception_suppresses_new_recover
    parser = RuntimeParserTest::RecoveringStatements.new([[:BAD, nil], [";", nil]])
    events = observe(parser)
    parser.define_singleton_method(:on_error_recover) { |*| raise "recover failed" }

    assert_raises(RuntimeError) { parser.do_parse }
    refute_includes events.map(&:type), :recover
    refute_includes events.map(&:type), :reject
  end

  def test_push_hook_exception_finishes_session_without_reject
    parser = RuntimeParserTest::Calculator.new([])
    events = observe(parser)
    parser.define_singleton_method(:on_shift) { |*| raise "shift failed" }

    assert_raises(RuntimeError) { parser.push(:INT, 1) }
    refute_includes events.map(&:type), :shift
    refute_includes events.map(&:type), :reject
    error = assert_raises(Ibex::ParseError) { parser.finish }
    assert_match(/push session is finished/, error.message)
  end

  # rubocop:disable Metrics/AbcSize -- the four failure sources share the same no-success-event contract.
  def test_action_missing_goto_unknown_action_and_source_fail_without_success_events
    action = RuntimeParserTest::Calculator.new([[:INT, 1], ["+", nil], [:INT, 2]])
    action_events = observe(action)
    action.define_singleton_method(:add) { |*| raise "action failed" }
    assert_raises(RuntimeError) { action.do_parse }
    refute_includes action_events.map(&:type), :accept

    missing_class = Class.new(RuntimeParserTest::Calculator) do
      tables = RuntimeParserTest::Calculator::TABLES.merge(gotos: Array.new(9) { {} }).freeze
      define_singleton_method(:parser_tables) { tables }
    end
    missing = missing_class.new([[:INT, 1]])
    missing_events = observe(missing)
    assert_raises(Ibex::ParseError) { missing.do_parse }
    refute_includes missing_events.map(&:type), :reduce

    unknown_class = Class.new(RuntimeParserTest::Calculator) do
      tables = RuntimeParserTest::Calculator::TABLES.merge(actions: [[[:unknown]]]).freeze
      define_singleton_method(:parser_tables) { tables }
    end
    unknown = unknown_class.new([])
    unknown_events = observe(unknown)
    assert_raises(Ibex::ParseError) { unknown.do_parse }
    assert_equal [:start], unknown_events.map(&:type)

    source = RuntimeParserTest::Calculator.new([])
    source_events = observe(source)
    source.define_singleton_method(:next_token) { raise "source failed" }
    assert_raises(RuntimeError) { source.do_parse }
    assert_equal [:start], source_events.map(&:type)
  end
  # rubocop:enable Metrics/AbcSize

  def test_recovery_eof_is_the_only_reject_and_later_error_is_reported
    tokens = [[:BAD, nil], [";", nil], [:INT, 1], [";", nil], [:BAD, nil], [";", nil]]
    parser = RuntimeParserTest::RecoveringStatements.new(tokens)
    events = observe(parser)

    assert_equal %i[error error], parser.do_parse
    assert_equal(2, events.count { |event| event.type == :error })
    assert_equal(2, events.count { |event| event.type == :recover })
    refute_includes events.map(&:type), :reject

    eof = RuntimeParserTest::RecoveringStatements.new([[:BAD, nil]])
    eof_events = observe(eof)
    assert_nil eof.do_parse
    reasons = eof_events.filter_map do |event|
      event.data["reason"] if event.type == :reject
    end
    assert_equal ["eof_during_recovery"], reasons
  end

  def test_lifecycle_errors_do_not_add_start_or_terminal_events
    parser = RuntimeParserTest::Calculator.new([])
    events = observe(parser)
    assert_raises(Ibex::ParseError) { parser.push(nil) }
    assert_empty events

    parser.push(:INT, 1)
    assert_equal 1, parser.finish
    count = events.length
    assert_raises(Ibex::ParseError) { parser.finish }
    assert_equal count, events.length
  end

  private

  def observe(parser)
    events = []
    parser.observe { |event| events << event }
    events
  end
end
