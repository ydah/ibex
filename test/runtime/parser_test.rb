# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"

# rubocop:disable Metrics/ClassLength -- cases cover one stateful runtime contract.
class RuntimeParserTest < Minitest::Test
  class Calculator < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { INT: 2, "+" => 3, "(" => 4, ")" => 5 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "INT", 3 => "+", 4 => "(", 5 => ")" },
      actions: [
        { 2 => [:shift, 3], 4 => [:shift, 4] },
        { 0 => [:accept], 3 => [:shift, 5] },
        { 0 => [:reduce, 1], 3 => [:reduce, 1], 5 => [:reduce, 1] },
        { 0 => [:reduce, 2], 3 => [:reduce, 2], 5 => [:reduce, 2] },
        { 2 => [:shift, 3], 4 => [:shift, 4] },
        { 2 => [:shift, 3], 4 => [:shift, 4] },
        { 3 => [:shift, 5], 5 => [:shift, 8] },
        { 0 => [:reduce, 0], 3 => [:reduce, 0], 5 => [:reduce, 0] },
        { 0 => [:reduce, 3], 3 => [:reduce, 3], 5 => [:reduce, 3] }
      ],
      gotos: [
        { 6 => 1, 7 => 2 }, {}, {}, {}, { 6 => 6, 7 => 2 }, { 7 => 7 }, {}, {}, {}
      ],
      productions: [
        { lhs: 6, length: 3, action: :add },
        { lhs: 6, length: 1 },
        { lhs: 7, length: 1 },
        { lhs: 7, length: 3, action: :parenthesized }
      ]
    }.freeze

    def self.parser_tables = TABLES

    def initialize(tokens)
      super()
      @tokens = tokens
    end

    def next_token = @tokens.shift

    private

    def add(values, _stack) = values[0] + values[2]
    def parenthesized(values, _stack) = values[1]
  end

  class LegacyInitializerCalculator < Calculator
    attr_reader :application_state, :compatible_value_stacks

    # rubocop:disable Lint/MissingSuper -- this is the legacy Racc application pattern under test.
    def initialize(tokens)
      @tokens = tokens
      @application_state = :preserved
      @compatible_value_stacks = []
      @yydebug = true
      @yydebug_output = StringIO.new
    end
    # rubocop:enable Lint/MissingSuper

    def next_token
      @compatible_value_stacks << [@vstack.dup, @racc_vstack.dup, @vstack.equal?(@racc_vstack)]
      super
    end
  end

  class RecoveringStatements < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { INT: 2, ";" => 3 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "INT", 3 => ";" },
      actions: [
        { 1 => [:shift, 4], 2 => [:shift, 3] },
        { 0 => [:accept], 1 => [:shift, 4], 2 => [:shift, 3] },
        { 0 => [:reduce, 1], 1 => [:reduce, 1], 2 => [:reduce, 1] },
        { 3 => [:shift, 6] }, { 3 => [:shift, 7] },
        { 0 => [:reduce, 0], 1 => [:reduce, 0], 2 => [:reduce, 0] },
        { 0 => [:reduce, 2], 1 => [:reduce, 2], 2 => [:reduce, 2] },
        { 0 => [:reduce, 3], 1 => [:reduce, 3], 2 => [:reduce, 3] }
      ],
      gotos: [{ 4 => 1, 5 => 2 }, { 5 => 5 }, {}, {}, {}, {}, {}, {}],
      productions: [
        { lhs: 4, length: 2, action: :append },
        { lhs: 4, length: 1, action: :start },
        { lhs: 5, length: 2, action: :valid },
        { lhs: 5, length: 2, action: :invalid }
      ]
    }.freeze

    attr_reader :errors, :error_observations

    def self.parser_tables = TABLES

    def initialize(tokens)
      super()
      @tokens = tokens
      @errors = []
      @error_observations = []
    end

    def next_token = @tokens.shift

    def on_error(token_id, value, stack)
      @errors << token_to_str(token_id)
      @error_observations << [token_id, value, stack]
    end

    private

    def append(values, _stack) = values[0] + [values[1]]
    def start(values, _stack) = [values[0]]
    def valid(values, _stack) = values[0]
    def invalid(_values, _stack) = :error
  end

  class AcceptingCalculator < Calculator
    TABLES = Calculator::TABLES.merge(
      productions: Calculator::TABLES[:productions].each_with_index.map do |production, index|
        index == 2 ? production.merge(action: :accept_term) : production
      end
    ).freeze

    def self.parser_tables = TABLES

    private

    def accept_term(values, _stack)
      yyaccept
      values.first
    end
  end

  class RejectingCalculator < AcceptingCalculator
    private

    def accept_term(_values, _stack)
      yyerror
      nil
    end
  end

  class ResettingStatements < RecoveringStatements
    TABLES = RecoveringStatements::TABLES.merge(
      productions: RecoveringStatements::TABLES[:productions].each_with_index.map do |production, index|
        index == 3 ? production.merge(action: :invalid_and_reset) : production
      end
    ).freeze

    def self.parser_tables = TABLES

    private

    def invalid_and_reset(_values, _stack)
      yyerrok
      :error
    end
  end

  class LocationAwareRecoveringStatements < RecoveringStatements
    LOCATION_ACTION = :_ibex_action_3 # rubocop:disable Naming/VariableNumber
    TABLES = RecoveringStatements::TABLES.merge(
      productions: RecoveringStatements::TABLES[:productions].each_with_index.map do |production, index|
        index == 3 ? production.merge(action: LOCATION_ACTION, location_action: true) : production
      end
    ).freeze

    def self.parser_tables = TABLES

    private

    define_method(LOCATION_ACTION) do |_values, _stack, locations, _location_stack, location|
      [locations, location]
    end
  end

  class LookaheadCorrectionParser < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { A: 2, B: 3 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "A", 3 => "B" },
      actions: [{ 3 => [:error] }, { 2 => [:shift, 2] }, { 0 => [:accept] }],
      gotos: [{ 4 => 1 }, {}, {}],
      default_actions: [[:reduce, 0], nil, nil],
      productions: [{ lhs: 4, length: 0 }]
    }.freeze

    attr_reader :exact_at_error

    def self.parser_tables = TABLES

    def initialize(tokens)
      super()
      @tokens = tokens
    end

    def next_token = @tokens.shift

    def on_error(token_id, value, stack)
      @exact_at_error = expected_tokens_exact
      super
    end
  end

  class ExtendedLookaheadCorrectionParser < LookaheadCorrectionParser
    TABLES = LookaheadCorrectionParser::TABLES.merge(exact_expected_tokens: true).freeze

    def self.parser_tables = TABLES
  end

  class CyclicLookaheadCorrectionParser < LookaheadCorrectionParser
    TABLES = LookaheadCorrectionParser::TABLES.merge(
      exact_expected_tokens: true,
      gotos: [{ 4 => 0 }, {}, {}]
    ).freeze

    def self.parser_tables = TABLES
  end

  def test_do_parse_handles_symbol_string_and_false_eof
    parser = Calculator.new([[:INT, 1], ["+", "+"], ["(", "("], [:INT, 2], ["+", "+"], [:INT, 3], [")", ")"], false])
    assert_equal 6, parser.do_parse
  end

  def test_nil_is_eof
    assert_equal 7, Calculator.new([[:INT, 7], nil]).do_parse
  end

  def test_parser_exposes_the_compatible_parse_error_constant
    assert_same Ibex::Runtime::ParseError, Ibex::Runtime::Parser::ParseError
  end

  def test_application_initializer_without_super_gets_runtime_defaults_lazily
    parser = LegacyInitializerCalculator.new([[:INT, 7], nil])
    events = []
    subscription = parser.observe { |event| events << event.type }

    assert_instance_of Ibex::Runtime::ResourceLimits, parser.resource_limits
    assert parser.yydebug
    assert_equal 7, parser.do_parse
    assert_equal :preserved, parser.application_state
    assert parser.unobserve(subscription)
    assert_includes events, :accept
    assert_includes parser.compatible_value_stacks, [[7], [7], true]
  end

  def test_yyparse_uses_yielded_tokens
    source = Object.new
    source.define_singleton_method(:tokens) { |&block| [[:INT, 2], ["+", nil], [:INT, 4]].each(&block) }
    assert_equal 6, Calculator.new([]).yyparse(source, :tokens)
  end

  def test_default_error_has_token_and_expected_tokens
    error = assert_raises(Ibex::ParseError) { Calculator.new([["+", nil]]).do_parse }
    assert_match(/\(input\):1:1: unexpected \+/, error.message)
    assert_match(/expected INT, \(/, error.message)
  end

  def test_explicit_exact_expected_tokens_simulates_default_reductions
    parser = LookaheadCorrectionParser.new([[:B, nil]])
    error = assert_raises(Ibex::ParseError) { parser.do_parse }

    assert_equal %w[$eof A], error.expected_tokens
    assert_equal ["A"], parser.exact_at_error
  end

  def test_extended_expected_tokens_uses_lookahead_correction
    parser = ExtendedLookaheadCorrectionParser.new([[:B, nil]])
    error = assert_raises(Ibex::ParseError) { parser.do_parse }

    assert_equal ["A"], error.expected_tokens
    assert_equal ["A"], parser.exact_at_error
  end

  def test_exact_expected_tokens_fail_closed_on_a_reduction_cycle
    parser = CyclicLookaheadCorrectionParser.new([[:B, nil]])
    error = assert_raises(Ibex::ParseError) { parser.do_parse }

    assert_empty error.expected_tokens
    assert_empty parser.exact_at_error
  end

  def test_recovery_discards_bad_input_and_continues
    parser = RecoveringStatements.new([[:INT, 1], [:BAD, nil], [";", nil], [:INT, 2], [";", nil]])
    assert_equal [:error, 2], parser.do_parse
    assert_equal [":BAD"], parser.errors
  end

  def test_undeclared_unknown_token_is_reported_before_recovery
    parser = RecoveringStatements.new([[:BAD, "payload"], [";", nil]])
    assert_equal [:error], parser.do_parse
    token_id, value, stack = parser.error_observations.fetch(0)
    assert_operator token_id, :<, 0
    assert_equal "payload", value
    assert_equal [], stack
    assert_equal ":BAD", parser.token_to_str(token_id)
  end

  def test_undeclared_unknown_token_uses_the_default_error_handler
    error = assert_raises(Ibex::ParseError) { Calculator.new([[:BAD, "payload"]]).do_parse }
    assert_match(/unexpected :BAD/, error.message)
    assert_match(/payload/, error.message)
  end

  def test_recovery_reports_again_after_three_successful_shifts
    tokens = [[:BAD, nil], [";", nil], [:INT, 1], [";", nil], [:BAD, nil], [";", nil]]
    parser = RecoveringStatements.new(tokens)
    parser.do_parse
    assert_equal [":BAD", ":BAD"], parser.errors
  end

  def test_error_recovery_keeps_the_location_stack_parallel
    unexpected = { file: "recover.txt", line: 2, column: 3 }
    semicolon = { file: "recover.txt", line: 2, column: 7 }
    parser = LocationAwareRecoveringStatements.new([[:BAD, nil, unexpected], [";", nil, semicolon]])

    locations, span = parser.do_parse.fetch(0)

    assert_same unexpected, locations.fetch(0)
    assert_same semicolon, locations.fetch(1)
    assert_same unexpected, span.start
    assert_same semicolon, span.finish
  end

  def test_yyerrok_resumes_error_reporting_immediately
    parser = ResettingStatements.new([[:BAD, nil], [";", nil], [:INT, 1], [:BAD, nil], [";", nil]])
    parser.do_parse
    assert_equal [":BAD", ":BAD"], parser.errors
  end

  def test_yyaccept_accepts_the_current_reduction
    assert_equal 7, AcceptingCalculator.new([[:INT, 7], ["+", nil], [:BAD, nil]]).do_parse
  end

  def test_reduce_hook_runs_once_before_yyaccept_terminates
    parser = AcceptingCalculator.new([[:INT, 7], ["+", nil], [:BAD, nil]])
    reductions = []
    parser.define_singleton_method(:on_reduce) do |*payload|
      reductions << payload
      :ignored_return
    end

    assert_equal 7, parser.do_parse
    assert_equal [[2, [7], 7]], reductions
  end

  def test_yyerror_enters_recovery_without_calling_on_error
    assert_nil RejectingCalculator.new([[:INT, 7]]).do_parse
  end

  def test_shift_and_reduce_hooks_report_committed_events_in_order
    parser = Calculator.new([[:INT, 1], ["+", :plus], [:INT, 2]])
    events = []
    parser.define_singleton_method(:on_shift) { |*payload| events << [:shift, *payload] }
    parser.define_singleton_method(:on_reduce) { |*payload| events << [:reduce, *payload] }

    assert_equal 3, parser.do_parse
    assert_equal [
      [:shift, 2, 1, 3],
      [:reduce, 2, [1], 1],
      [:reduce, 1, [1], 1],
      [:shift, 3, :plus, 5],
      [:shift, 2, 2, 3],
      [:reduce, 2, [2], 2],
      [:reduce, 0, [1, :plus, 2], 3]
    ], events
  end

  def test_recovery_hook_preserves_the_original_error_context
    parser = RecoveringStatements.new([[:INT, 99], [:BAD, "payload"], [";", :semicolon]])
    errors = []
    shifts = []
    recoveries = []
    parser.define_singleton_method(:on_error) do |token_id, value, value_stack|
      errors << [token_id, value, value_stack.dup]
      value_stack.clear
    end
    parser.define_singleton_method(:on_shift) { |*payload| shifts << payload }
    parser.define_singleton_method(:on_error_recover) do |token_id, value, value_stack|
      recoveries << [token_id, value, value_stack, expected_tokens]
    end

    assert_equal [:error], parser.do_parse
    token_id, value, value_stack = errors.fetch(0)
    assert_equal [[2, 99, 3], [3, :semicolon, 7]], shifts
    refute_includes shifts.map(&:first), Ibex::Runtime::Parser::ERROR_TOKEN
    assert_equal [[token_id, value, value_stack, [";"]]], recoveries
  end

  def test_location_recovery_and_discard_hooks_preserve_the_original_token
    bad_location = Ibex::Location.new(file: "recover.txt", line: 2, column: 4)
    semicolon_location = Ibex::Location.new(file: "recover.txt", line: 2, column: 8)
    parser = RecoveringStatements.new([[:BAD, "payload", bad_location], [";", nil, semicolon_location]])
    recoveries = []
    discards = []
    parser.define_singleton_method(:on_error_recover_location) do |*payload|
      recoveries << payload
    end
    parser.define_singleton_method(:on_discard) { |*payload| discards << payload }

    assert_equal [:error], parser.do_parse
    token_id = parser.error_observations.fetch(0).fetch(0)
    assert_equal [[token_id, "payload", [], bad_location, 4]], recoveries
    assert_equal [[token_id, "payload", bad_location, :recovery]], discards
  end

  def test_recovery_hook_runs_for_yyerror_without_calling_on_error
    parser = RecoveringStatements.new([[:INT, 1], [";", nil]])
    recoveries = []
    events = []
    parser.define_singleton_method(:valid) do |_values, _stack|
      yyerror
      :semantic_error
    end
    parser.define_singleton_method(:on_reduce) { |*| events << :reduce }
    parser.define_singleton_method(:on_error_recover) do |*payload|
      events << :recover
      recoveries << payload
    end

    assert_nil parser.do_parse
    assert_empty parser.errors
    assert_equal %i[reduce recover], events
    assert_equal [[0, nil, [:semantic_error]]], recoveries
  end

  def test_recovery_hook_is_not_called_when_the_error_token_cannot_shift
    parser = Calculator.new([["+", nil]])
    recoveries = []
    parser.define_singleton_method(:on_error) { |_token_id, _value, _stack| nil }
    parser.define_singleton_method(:on_error_recover) { |*payload| recoveries << payload }

    assert_nil parser.do_parse
    assert_empty recoveries
  end

  def test_hook_exceptions_propagate
    cases = [
      [Calculator.new([[:INT, 1]]), :on_shift],
      [Calculator.new([[:INT, 1]]), :on_reduce],
      [RecoveringStatements.new([[:BAD, nil], [";", nil]]), :on_error_recover]
    ]

    cases.each do |parser, hook|
      parser.define_singleton_method(hook) { |*| raise "#{hook} failed" }
      error = assert_raises(RuntimeError) { parser.do_parse }
      assert_equal "#{hook} failed", error.message
    end
  end

  def test_hook_return_values_do_not_change_a_normal_parse_result
    parser = Calculator.new([[:INT, 1], ["+", nil], [:INT, 2]])
    sentinel = Object.new
    calls = []
    parser.define_singleton_method(:on_shift) do |*|
      calls << :shift
      sentinel
    end
    parser.define_singleton_method(:on_reduce) do |*|
      calls << :reduce
      sentinel
    end

    assert_equal 3, parser.do_parse
    assert_includes calls, :shift
    assert_includes calls, :reduce
  end

  def test_hook_return_values_do_not_change_a_recovery_parse_result
    tokens = [[:BAD, nil], [";", nil], [:INT, 2], [";", nil]]
    parser = RecoveringStatements.new(tokens)
    sentinel = Object.new
    calls = []
    parser.define_singleton_method(:on_shift) do |*|
      calls << :shift
      sentinel
    end
    parser.define_singleton_method(:on_reduce) do |*|
      calls << :reduce
      sentinel
    end
    parser.define_singleton_method(:on_error_recover) do |*|
      calls << :recover
      sentinel
    end

    assert_equal [:error, 2], parser.do_parse
    assert_includes calls, :shift
    assert_includes calls, :reduce
    assert_includes calls, :recover
  end

  def test_debug_trace_reports_core_operations
    output = StringIO.new
    parser = Calculator.new([[:INT, 1]])
    parser.yydebug = true
    parser.yydebug_output = output
    parser.do_parse
    assert_includes output.string, "read INT"
    assert_includes output.string, "shift INT"
    assert_includes output.string, "reduce"
    refute_includes output.string, "value="
  end

  def test_dormant_debug_does_not_dispatch_trace_payloads
    parsers = [
      Calculator.new([[:INT, 1], ["+", nil], [:INT, 2]]),
      RecoveringStatements.new([[:BAD, nil], [";", nil]])
    ]

    parsers.each do |parser|
      trace_calls = 0
      parser.define_singleton_method(:trace) { |_message| trace_calls += 1 }
      parser.trace_value_printer = ->(_value) { flunk "dormant debug rendered a value" }

      parser.do_parse
      assert_equal 0, trace_calls
    end
  end

  def test_debug_trace_bytes_and_printer_failure_containment_are_stable
    output = StringIO.new
    parser = Calculator.new([[:INT, 1], ["+", :plus], [:INT, 2]])
    parser.yydebug = true
    parser.yydebug_output = output
    parser.trace_value_printer = ->(value) { value == :plus ? raise("hidden") : "<#{value}>" }

    assert_equal 3, parser.do_parse
    assert_equal <<~TRACE, output.string
      ibex: start state 0
      ibex: read INT
      ibex: shift INT value=<1> -> state 3
      ibex: read +
      ibex: reduce 2 (1) value=<1> -> state 2
      ibex: reduce 1 (1) value=<1> -> state 1
      ibex: shift + value=<printer error: RuntimeError> -> state 5
      ibex: read INT
      ibex: shift INT value=<2> -> state 3
      ibex: read $eof
      ibex: reduce 2 (1) value=<2> -> state 7
      ibex: reduce 0 (3) value=<3> -> state 1
    TRACE
  end

  def test_debug_trace_value_printer_is_opt_in_and_contains_formatter_failures
    output = StringIO.new
    parser = Calculator.new([[:INT, 1], ["+", :plus], [:INT, 2]])
    parser.yydebug = true
    parser.yydebug_output = output
    parser.trace_value_printer = ->(value) { value == :plus ? raise("hidden") : "<#{value}>" }

    assert_equal 3, parser.do_parse
    assert_includes output.string, "shift INT value=<1>"
    assert_includes output.string, "shift + value=<printer error: RuntimeError>"
  end
end
# rubocop:enable Metrics/ClassLength
