# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"

class RuntimeSyncRecoveryTest < Minitest::Test
  class PopStateSyncParser < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { ITEM: 2, ";" => 3, BAD: 4 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "ITEM", 3 => ";", 4 => "BAD" },
      actions: [
        { 2 => [:shift, 1], 3 => [:shift, 3] },
        { 4 => [:reduce, 0] },
        { 4 => [:error] },
        { 0 => [:accept] },
        {}
      ],
      gotos: [{ 5 => 2, 6 => 4 }, {}, {}, {}, {}],
      productions: [{ lhs: 5, length: 1 }, { lhs: 6, length: 1 }],
      eager_reductions: [nil, nil, [:reduce, 1], nil, nil],
      recovery_sync_tokens: [3]
    }.freeze

    attr_reader :recovery_states

    def self.parser_tables = TABLES

    def initialize
      super
      @recovery_states = []
    end

    def parse_tokens(tokens)
      @tokens = tokens
      do_parse
    end

    def next_token = @tokens.shift
    def on_error(*) = nil

    def on_error_recover_location(_token_id, _value, _stack, _location, state)
      @recovery_states << state
    end
  end

  SYNC_GRAMMAR = <<~GRAMMAR
    class SyncParser
    pragma extended
    token ITEM BAD
    %recover sync: ';'
    rule
    program: statements
    statements: statements statement | statement
    statement: ITEM ';'
    end
    ---- inner
    attr_reader :errors, :recoveries, :discarded
    def initialize
      super
      @errors = []
      @recoveries = []
      @discarded = []
    end
    def parse_tokens(tokens) = (@tokens = tokens; do_parse)
    def next_token = @tokens.shift
    def on_error(token_id, value, _stack) = @errors << [token_to_str(token_id), value]
    def on_error_recover(token_id, value, _stack) = @recoveries << [token_to_str(token_id), value]
    def on_discard(_token_id, value, _location, reason) = @discarded << [value, reason]
  GRAMMAR
  EXPLICIT_GRAMMAR = <<~GRAMMAR
    class ExplicitRecoveryParser
    pragma extended
    token BAD
    %recover sync: ';'
    rule
    start: error ';' { result = :explicit }
    end
    ---- inner
    def parse_tokens(tokens) = (@tokens = tokens; do_parse)
    def next_token = @tokens.shift
    def on_error(*) = nil
  GRAMMAR
  PUSH_GRAMMAR = <<~GRAMMAR
    class PushSyncParser
    pragma extended
    token ITEM BAD
    %recover sync: ';'
    rule
    start: ITEM ';'
    end
    ---- inner
    attr_reader :errors, :recoveries
    def initialize
      super
      @errors = 0
      @recoveries = 0
    end
    def on_error(*) = @errors += 1
    def on_error_recover(*) = @recoveries += 1
  GRAMMAR
  ERROR_REDUCE_GRAMMAR = <<~GRAMMAR
    class ErrorReduceParser
    pragma extended
    token NUM BAD
    %on_error_reduce expression
    rule
    start: expression ';'
    expression: NUM { result = :expression }
    end
    ---- inner
    attr_reader :error_stack
    def parse_tokens(tokens) = (@tokens = tokens; do_parse)
    def next_token = @tokens.shift
    def on_error(_token_id, _value, stack) = @error_stack = stack
  GRAMMAR

  def test_discards_until_a_declared_sync_token_and_resumes
    parser = generate(SYNC_GRAMMAR).new
    result = parser.parse_tokens(
      [%i[ITEM first], %i[BAD bad1], %i[BAD bad2], [";", nil], %i[ITEM second], [";", nil]]
    )

    assert_equal :first, result
    assert_equal [["BAD", :bad1]], parser.errors
    assert_equal [["BAD", :bad1]], parser.recoveries
    assert_equal [%i[bad1 recovery], %i[bad2 recovery]], parser.discarded
  end

  def test_explicit_error_production_takes_priority_over_sync_recovery
    assert_equal :explicit, generate(EXPLICIT_GRAMMAR).new.parse_tokens([[:BAD, nil], [";", nil]])
  end

  def test_push_driver_keeps_sync_recovery_context_between_tokens
    parser = generate(PUSH_GRAMMAR).new

    assert_equal :need_more, parser.push(:ITEM, :item)
    assert_equal :need_more, parser.push(:BAD, :bad)
    assert_equal :need_more, parser.push(";", nil)
    assert_equal 1, parser.errors
    assert_equal 1, parser.recoveries
    assert_equal :item, parser.finish
  end

  def test_pull_sync_recovery_does_not_dispatch_dormant_trace_payloads
    parser = generate(SYNC_GRAMMAR).new
    trace_calls = 0
    parser.define_singleton_method(:trace) { |_message| trace_calls += 1 }

    result = parser.parse_tokens(
      [%i[ITEM first], %i[BAD bad1], %i[BAD bad2], [";", nil], %i[ITEM second], [";", nil]]
    )

    assert_equal :first, result
    assert_equal 0, trace_calls
    assert_equal [["BAD", :bad1]], parser.recoveries
  end

  def test_push_sync_recovery_does_not_dispatch_dormant_trace_payloads
    parser = generate(PUSH_GRAMMAR).new
    trace_calls = 0
    parser.define_singleton_method(:trace) { |_message| trace_calls += 1 }

    assert_equal :need_more, parser.push(:ITEM, :item)
    assert_equal :need_more, parser.push(:BAD, :bad)
    assert_equal :need_more, parser.push(";", nil)
    assert_equal :item, parser.finish
    assert_equal 0, trace_calls
  end

  def test_sync_recovery_debug_message_bytes_are_stable
    parser = generate(SYNC_GRAMMAR).new
    output = StringIO.new
    parser.yydebug = true
    parser.yydebug_output = output

    parser.parse_tokens([%i[ITEM first], %i[BAD bad], [";", nil]])

    assert_equal ["ibex: recover: synchronized before ';' in state 1\n"],
                 output.string.lines.grep(/synchronized/)
  end

  def test_pull_sync_recovery_pop_does_not_dispatch_dormant_trace_payloads
    parser = PopStateSyncParser.new
    trace_calls = 0
    parser.define_singleton_method(:trace) { |_message| trace_calls += 1 }

    assert_equal :sync, parser.parse_tokens([%i[ITEM item], %i[BAD bad], [";", :sync]])
    assert_equal [0], parser.recovery_states
    assert_equal 0, trace_calls
  end

  def test_push_sync_recovery_pop_does_not_dispatch_dormant_trace_payloads
    parser = PopStateSyncParser.new
    trace_calls = 0
    parser.define_singleton_method(:trace) { |_message| trace_calls += 1 }

    assert_equal :need_more, parser.push(:ITEM, :item)
    assert_equal :need_more, parser.push(:BAD, :bad)
    assert_equal :need_more, parser.push(";", :sync)
    assert_equal :sync, parser.finish
    assert_equal [0], parser.recovery_states
    assert_equal 0, trace_calls
  end

  def test_sync_recovery_pop_debug_message_bytes_are_stable_for_pull_and_push
    pull = PopStateSyncParser.new
    pull_output = StringIO.new
    pull.yydebug = true
    pull.yydebug_output = pull_output
    assert_equal :sync, pull.parse_tokens([%i[ITEM item], %i[BAD bad], [";", :sync]])

    push = PopStateSyncParser.new
    push_output = StringIO.new
    push.yydebug = true
    push.yydebug_output = push_output
    push.push(:ITEM, :item)
    push.push(:BAD, :bad)
    push.push(";", :sync)
    assert_equal :sync, push.finish

    assert_equal ["ibex: recover: pop state 4 for sync token\n"],
                 pull_output.string.lines.grep(/for sync token/)
    assert_equal ["ibex: recover: pop state 2 for sync token\n"],
                 push_output.string.lines.grep(/for sync token/)
  end

  def test_on_error_reduce_commits_the_declared_semantic_reduction_before_reporting
    parser = generate(ERROR_REDUCE_GRAMMAR).new

    assert_nil parser.parse_tokens([[:NUM, 1], [:BAD, nil]])
    assert_equal [:expression], parser.error_stack
  end

  private

  def generate(source)
    ast = Ibex::Frontend::Parser.new(source, file: "recovery.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton, table: :compact).generate
    namespace = Module.new
    namespace.module_eval(generated, "generated-recovery.rb")
    namespace.const_get(grammar.class_name)
  end
end
