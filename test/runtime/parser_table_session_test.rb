# frozen_string_literal: true

require_relative "parser_test"

class RuntimeParserTableSessionTest < Minitest::Test
  def test_pull_looks_up_tables_once_per_session_and_refreshes_after_completion_and_failure
    parser_class = dynamic_calculator_class
    tokens = [[:INT, 1]]
    parser = parser_class.new(tokens)
    starts = []
    parser.observe { |event| starts << event.data.fetch("grammar_digest") if event.type == :start }

    parser_class.active_tables = tables_for("first")
    assert_equal 1, parser.do_parse
    assert_equal 1, parser_class.table_calls

    fail_shift = true
    parser.define_singleton_method(:on_shift) do |*|
      next unless fail_shift

      fail_shift = false
      raise "shift failed"
    end
    parser_class.active_tables = tables_for("second")
    tokens << [:INT, 2]
    assert_raises(RuntimeError) { parser.do_parse }
    assert_equal 2, parser_class.table_calls

    parser_class.active_tables = tables_for("third")
    tokens << [:INT, 3]
    assert_equal 3, parser.do_parse
    assert_equal 3, parser_class.table_calls
    assert_equal %w[first second third], starts
  end

  def test_push_keeps_tables_across_input_calls_and_refreshes_after_reset
    parser_class = dynamic_calculator_class
    parser = parser_class.new([])
    starts = []
    parser.observe { |event| starts << event.data.fetch("grammar_digest") if event.type == :start }

    parser_class.active_tables = tables_for("first")
    assert_equal :need_more, parser.push(:INT, 1)
    parser_class.active_tables = tables_for("unobserved")
    assert_equal 1, parser.finish
    assert_equal 1, parser_class.table_calls

    parser.reset_push
    parser_class.active_tables = tables_for("second")
    assert_equal :need_more, parser.push(:INT, 2)
    assert_equal 2, parser.finish
    assert_equal 2, parser_class.table_calls
    assert_equal %w[first second], starts
  end

  def test_push_failure_clears_tables_before_the_next_session
    parser_class = dynamic_calculator_class
    parser = parser_class.new([])
    starts = []
    parser.observe { |event| starts << event.data.fetch("grammar_digest") if event.type == :start }

    parser_class.active_tables = tables_for("failed")
    fail_shift = true
    parser.define_singleton_method(:on_shift) { |*| raise "shift failed" if fail_shift }
    assert_raises(RuntimeError) { parser.push(:INT, 3) }
    assert_equal 1, parser_class.table_calls

    parser.reset_push
    parser_class.active_tables = tables_for("recovered")
    fail_shift = false
    assert_equal :need_more, parser.push(:INT, 4)
    assert_equal 4, parser.finish
    assert_equal 2, parser_class.table_calls
    assert_equal %w[failed recovered], starts
  end

  def test_table_validation_failure_does_not_leave_a_stale_pull_or_push_session
    pull_class = dynamic_calculator_class
    pull_tokens = []
    pull = pull_class.new(pull_tokens)
    pull_class.active_tables = tables_for("invalid").merge(format_version: -1).freeze

    assert_raises(Ibex::ParseError) { pull.do_parse }
    pull_class.active_tables = tables_for("pull-valid")
    pull_tokens << [:INT, 5]
    assert_equal 5, pull.do_parse
    assert_equal 2, pull_class.table_calls

    push_class = dynamic_calculator_class
    push = push_class.new([])
    push_class.active_tables = tables_for("invalid").merge(format_version: -1).freeze

    assert_raises(Ibex::ParseError) { push.push(:INT, 6) }
    push.reset_push
    push_class.active_tables = tables_for("push-valid")
    assert_equal :need_more, push.push(:INT, 6)
    assert_equal 6, push.finish
    assert_equal 2, push_class.table_calls
  end

  private

  def dynamic_calculator_class
    Class.new(RuntimeParserTest::Calculator) do
      class << self
        attr_accessor :active_tables
        attr_reader :table_calls

        def parser_tables
          @table_calls = (@table_calls || 0) + 1
          @active_tables
        end
      end
    end
  end

  def tables_for(digest)
    RuntimeParserTest::Calculator::TABLES.merge(grammar_digest: digest).freeze
  end
end
