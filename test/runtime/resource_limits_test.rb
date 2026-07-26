# frozen_string_literal: true

require_relative "../test_helper"

class RuntimeResourceLimitsTest < Minitest::Test
  class RepeatingShiftParser < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { A: 2 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "A" },
      actions: [{ 0 => [:accept], 2 => [:shift, 0] }],
      gotos: [{}],
      productions: []
    }.freeze

    def self.parser_tables = TABLES

    def initialize(tokens, **arguments)
      super(**arguments)
      @tokens = tokens
    end

    def next_token = @tokens.shift
  end

  class RecoveringParser < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { BAD: 2 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "BAD" },
      actions: [{ 1 => [:shift, 1] }, { 0 => [:accept] }],
      gotos: [{}, {}],
      productions: []
    }.freeze

    attr_reader :error_calls

    def self.parser_tables = TABLES

    def initialize(tokens, **arguments)
      super(**arguments)
      @tokens = tokens
      @error_calls = 0
    end

    def next_token = @tokens.shift

    def on_error(_token_id, _value, _stack)
      @error_calls += 1
    end
  end

  def test_limits_are_validated_immutable_and_exposed
    limits = Ibex::Runtime::ResourceLimits.new(max_stack_depth: 8, max_recovery_attempts: 2)

    assert_equal({ max_stack_depth: 8, max_recovery_attempts: 2 }, limits.to_h)
    assert_predicate limits, :frozen?
    assert_same Ibex::Runtime::ResourceLimitError, Ibex::ResourceLimitError
    assert_raises(ArgumentError) { Ibex::Runtime::ResourceLimits.new(max_stack_depth: 0) }
    assert_raises(ArgumentError) { Ibex::Runtime::ResourceLimits.new(max_recovery_attempts: -1) }
  end

  def test_stack_depth_raises_a_structured_limit_error
    limits = Ibex::Runtime::ResourceLimits.new(max_stack_depth: 2)
    parser = RepeatingShiftParser.new([[:A, 1], [:A, 2]], resource_limits: limits)

    error = assert_raises(Ibex::ResourceLimitError) { parser.do_parse }

    assert_equal :stack_depth, error.resource
    assert_equal 2, error.limit
    assert_equal 3, error.observed
    assert_equal(
      { type: :resource_limit, resource: :stack_depth, limit: 2, observed: 3, state: 0, location: nil },
      error.to_h
    )
  end

  def test_recovery_attempt_budget_can_disable_or_allow_recovery
    disabled = Ibex::Runtime::ResourceLimits.new(max_recovery_attempts: 0)
    error = assert_raises(Ibex::ResourceLimitError) do
      RecoveringParser.new([[:BAD, nil]], resource_limits: disabled).do_parse
    end
    assert_equal :recovery_attempts, error.resource
    assert_equal 1, error.observed

    enabled = Ibex::Runtime::ResourceLimits.new(max_recovery_attempts: 1)
    parser = RecoveringParser.new([[:BAD, nil]], resource_limits: enabled)
    assert_nil parser.do_parse
    assert_equal 1, parser.error_calls
  end

  def test_limits_cannot_change_during_an_active_push_session
    parser = RecoveringParser.new([])
    assert_equal :need_more, parser.push(:BAD)

    error = assert_raises(Ibex::ParseError) do
      parser.resource_limits = Ibex::Runtime::ResourceLimits.new(max_stack_depth: 5)
    end
    assert_match(/cannot change during an active push session/, error.message)
  ensure
    parser&.reset_push
  end
end
