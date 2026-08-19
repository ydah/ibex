# frozen_string_literal: true

require_relative "parser_test"

class ParseSessionStateTest < Minitest::Test
  def test_parser_owns_stack_storage_through_one_session_state
    parser = RuntimeParserTest::Calculator.new([[:INT, 4]])

    assert_equal 4, parser.do_parse
    state = parser.parse_session_state
    assert_same parser.instance_variable_get(:@state_stack), state.state_stack
    assert_same parser.instance_variable_get(:@value_stack), state.value_stack
    assert_same parser.instance_variable_get(:@location_stack), state.location_stack
  end

  def test_reset_replaces_all_stack_storage_together
    parser = RuntimeParserTest::Calculator.new([])
    parser.push(:INT, 4)
    previous = parser.parse_session_state.state_stack

    parser.reset_push

    refute_same previous, parser.parse_session_state.state_stack
    assert_empty parser.parse_session_state.state_stack
    assert_empty parser.parse_session_state.value_stack
    assert_nil parser.parse_session_state.location_stack
    assert_same parser.parse_session_state.state_stack, parser.instance_variable_get(:@state_stack)
  end
end
