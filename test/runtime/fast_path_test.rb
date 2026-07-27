# frozen_string_literal: true

require_relative "parser_test"
require "stringio"

# rubocop:disable Metrics/ClassLength -- all gates exercise one session-eligibility contract.
class RuntimeFastPathTest < Minitest::Test
  class DeceptiveLocation
    attr_reader :file, :line, :column, :end_line, :end_column

    def initialize(file:, line:, column:, end_line:, end_column:)
      @file = file
      @line = line
      @column = column
      @end_line = end_line
      @end_column = end_column
    end

    def nil? = true
  end

  class ActionlessProbe < Ibex::Runtime::Parser
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { ITEM: 2 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "ITEM" },
      actions: [
        { 2 => [:shift, 1] },
        { 0 => [:reduce, 0] },
        { 0 => [:accept] }
      ],
      gotos: [{ 3 => 2 }, {}, {}],
      productions: [{ lhs: 3, length: 1, rhs: [2] }]
    }.freeze

    attr_reader :generic_shifts, :generic_reductions, :location_builds, :token_display_calls

    def self.parser_tables = TABLES

    def initialize(tokens = [])
      super()
      @tokens = tokens
      @generic_shifts = 0
      @generic_reductions = 0
      @location_builds = 0
      @token_display_calls = 0
    end

    def next_token = @tokens.shift

    def fast_path_active? = instance_variable_get(:@runtime_fast_path)
    def result_location = instance_variable_get(:@location_stack)&.last

    private

    def materialize_lookahead_token_display!
      @token_display_calls += 1
      super
    end

    def shift(next_state)
      @generic_shifts += 1
      super
    end

    def reduce(production_id, prefetched_production = nil)
      @generic_reductions += 1
      super
    end

    def pop_reduction_locations(length)
      @location_builds += 1
      super
    end
  end

  class EmptyProbe < ActionlessProbe
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: {},
      token_names: { 0 => "$eof", 1 => "error" },
      actions: [
        { 0 => [:reduce, 0] },
        { 0 => [:accept] }
      ],
      gotos: [{ 2 => 1 }, {}],
      productions: [{ lhs: 2, length: 0, rhs: [] }]
    }.freeze

    def self.parser_tables = TABLES
  end

  class ActionInstrumentationProbe < ActionlessProbe
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { ITEM: 2 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "ITEM" },
      actions: [
        { 2 => [:shift, 1] },
        { 0 => [:reduce, 0] },
        { 0 => [:reduce, 1] },
        { 0 => [:accept] }
      ],
      gotos: [{ 3 => 3, 4 => 2 }, {}, {}, {}],
      productions: [
        { lhs: 4, length: 1, rhs: [2], action: :install_instrumentation },
        { lhs: 3, length: 1, rhs: [4] }
      ]
    }.freeze

    def self.parser_tables = TABLES

    attr_writer :instrumentation

    private

    def install_instrumentation(values, _stack)
      @instrumentation&.call(self)
      values.first
    end
  end

  class TokenDisplayProbe < ActionInstrumentationProbe
    attr_accessor :display_phase
    attr_writer :display_effect

    def initialize(...)
      super
      @display_phase = :read
    end

    def token_to_str(token_id)
      @display_effect&.call(self, token_id)
      "#{@display_phase}:#{super}"
    end
  end

  class MethodOverrideProbe < ActionlessProbe
    attr_reader :method_helper_calls

    def initialize(...)
      super
      @method_helper_calls = []
    end

    def method(name)
      @method_helper_calls << name
      raise "application method helper must remain dormant"
    end
  end

  class ControlProbe < ActionlessProbe
    TABLES = {
      format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
      tokens: { ITEM: 2 },
      token_names: { 0 => "$eof", 1 => "error", 2 => "ITEM" },
      actions: [
        { 2 => [:shift, 1] },
        { 0 => [:reduce, 0] },
        { 0 => [:reduce, 1] },
        { 0 => [:accept] }
      ],
      gotos: [{ 3 => 3, 4 => 2 }, {}, {}, {}],
      productions: [
        { lhs: 4, length: 1, rhs: [2] },
        { lhs: 3, length: 1, rhs: [4], action: :transform }
      ]
    }.freeze

    attr_reader :transform_calls
    attr_writer :before_token

    def self.parser_tables = TABLES

    def initialize(...)
      super
      @transform_calls = 0
    end

    def next_token
      before_token = @before_token
      @before_token = nil
      before_token&.call(self)
      super
    end

    private

    def transform(values, _stack)
      @transform_calls += 1
      [values.first, :transformed]
    end
  end

  class OverriddenControlProbe < ControlProbe
    def yyerror
      @semantic_error = true
      nil
    end

    def yyaccept
      @accept_requested = true
      nil
    end
  end

  class ForcedGenericOverriddenControlProbe < OverriddenControlProbe
    def on_shift(...)
      @forced_generic_shift = true
      super
    end
  end

  def test_eligible_pull_and_push_skip_generic_runtime_builders
    pull = ActionlessProbe.new([[:ITEM, "pull"], false])

    assert_equal "pull", pull.do_parse
    assert_equal [0, 0, 0, 0],
                 [pull.generic_shifts, pull.generic_reductions, pull.location_builds, pull.token_display_calls]
    refute pull.fast_path_active?

    push = ActionlessProbe.new
    assert_equal :need_more, push.push(:ITEM, "push")
    assert push.fast_path_active?
    assert_equal "push", push.finish
    assert_equal [0, 0, 0, 0],
                 [push.generic_shifts, push.generic_reductions, push.location_builds, push.token_display_calls]
  end

  def test_application_method_helper_is_not_used_for_eligibility_introspection
    parser = MethodOverrideProbe.new([[:ITEM, 9], false])

    assert_equal 9, parser.do_parse
    assert_empty parser.method_helper_calls
    assert_equal [0, 0], [parser.generic_shifts, parser.generic_reductions]
  end

  def test_undefined_hook_falls_back_without_raising_before_generic_dispatch
    undefined_hook_class = Class.new(ActionlessProbe) do
      attr_reader :lexer_calls

      undef_method :on_shift

      def next_token
        @lexer_calls = (@lexer_calls || 0) + 1
        super
      end
    end
    parser = undefined_hook_class.new([[:ITEM, 1], false])

    assert_raises(NoMethodError) { parser.do_parse }
    assert_equal 1, parser.lexer_calls
    assert_equal 1, parser.generic_shifts
  end

  def test_debug_and_observation_disqualify_the_session
    debug = ActionlessProbe.new([[:ITEM, 1], false])
    debug.yydebug = true
    debug.yydebug_output = StringIO.new
    assert_equal 1, debug.do_parse
    assert_operator debug.generic_shifts, :>, 0
    assert_operator debug.generic_reductions, :>, 0

    observed = ActionlessProbe.new([[:ITEM, 2], false])
    events = []
    observed.observe { |event| events << event.type }
    assert_equal 2, observed.do_parse
    assert_operator observed.generic_shifts, :>, 0
    assert_includes events, :shift
  end

  def test_repair_cst_and_declared_locations_disqualify_the_session
    repaired = ActionlessProbe.new
    repaired.repair_policy = Ibex::Runtime::RepairPolicy.new
    assert_equal :need_more, repaired.push(:ITEM, 3)
    assert_operator repaired.generic_shifts, :>, 0

    cst_class = Class.new(ActionlessProbe) do
      tables = ActionlessProbe::TABLES.merge(cst: true).freeze
      define_singleton_method(:parser_tables) { tables }
    end
    cst = cst_class.new
    assert_equal :need_more, cst.push(:ITEM, 4)
    assert_operator cst.generic_shifts, :>, 0

    located_class = Class.new(ActionlessProbe) do
      tables = ActionlessProbe::TABLES.merge(uses_locations: true).freeze
      define_singleton_method(:parser_tables) { tables }
    end
    located = located_class.new
    assert_equal :need_more, located.push(:ITEM, 5)
    assert_operator located.generic_shifts, :>, 0
  end

  def test_each_shift_and_reduce_hook_override_disqualifies_the_session
    %i[on_shift on_shift_location on_reduce on_reduce_location].each do |hook|
      hooked_class = Class.new(ActionlessProbe) do
        attr_reader :hook_calls

        define_method(hook) do |*|
          @hook_calls = (@hook_calls || 0) + 1
        end
      end
      parser = hooked_class.new([[:ITEM, hook], false])

      assert_equal hook, parser.do_parse
      assert_operator parser.hook_calls, :>, 0
      assert_operator parser.generic_shifts, :>, 0
      assert_operator parser.generic_reductions, :>, 0
    end
  end

  def test_singleton_and_prepended_hooks_disqualify_the_session
    singleton = ActionlessProbe.new([[:ITEM, 1], false])
    singleton_calls = []
    singleton.define_singleton_method(:on_reduce) { |*payload| singleton_calls << payload }
    assert_equal 1, singleton.do_parse
    refute_empty singleton_calls
    assert_operator singleton.generic_reductions, :>, 0

    layer = Module.new do
      def on_shift(*payload)
        (@layer_calls ||= []) << payload
        super
      end

      attr_reader :layer_calls
    end
    prepended_class = Class.new(ActionlessProbe)
    prepended_class.prepend(layer)
    prepended = prepended_class.new([[:ITEM, 2], false])
    assert_equal 2, prepended.do_parse
    refute_empty prepended.layer_calls
    assert_operator prepended.generic_shifts, :>, 0
  end

  def test_subclass_singleton_and_prepended_token_display_overrides_disqualify_the_session
    subclass = TokenDisplayProbe.new([[:ITEM, 1], false])
    assert_equal 1, subclass.do_parse
    assert_operator subclass.generic_shifts, :>, 0

    singleton = ActionlessProbe.new([[:ITEM, 2], false])
    singleton.define_singleton_method(:token_to_str) do |token_id|
      Ibex::Runtime::Parser.instance_method(:token_to_str).bind_call(self, token_id)
    end
    assert_equal 2, singleton.do_parse
    assert_operator singleton.generic_shifts, :>, 0

    layer = Module.new do
      attr_reader :layer_token_display_calls

      def token_to_str(token_id)
        @layer_token_display_calls = (@layer_token_display_calls || 0) + 1
        super
      end
    end
    prepended_class = Class.new(ActionlessProbe)
    prepended_class.prepend(layer)
    prepended = prepended_class.new([[:ITEM, 3], false])
    assert_equal 3, prepended.do_parse
    assert_operator prepended.generic_shifts, :>, 0
    assert_operator prepended.layer_token_display_calls, :>, 0
  end

  def test_pull_and_push_locations_disable_before_the_affected_operation
    location = { file: "input.txt", line: 1, column: 1 }
    pull = ActionlessProbe.new([[:ITEM, "pull", location], false])
    assert_equal "pull", pull.do_parse
    assert_operator pull.generic_shifts, :>, 0
    assert_operator pull.generic_reductions, :>, 0

    push = ActionlessProbe.new
    assert_equal :need_more, push.push(:ITEM, "push", location)
    assert_operator push.generic_shifts, :>, 0
    assert_equal "push", push.finish
    assert_operator push.generic_reductions, :>, 0

    eof_location = ActionlessProbe.new
    assert_equal :need_more, eof_location.push(:ITEM, "eof")
    assert_equal 0, eof_location.generic_shifts
    assert_equal "eof", eof_location.finish(location: location)
    assert_operator eof_location.generic_reductions, :>, 0

    false_location = ActionlessProbe.new
    assert_equal :need_more, false_location.push(:ITEM, "false", false)
    assert_operator false_location.generic_shifts, :>, 0
  end

  def test_deceptive_pull_location_cannot_hide_from_the_fast_path_gate
    location = deceptive_location(line: 2)
    parser = ActionlessProbe.new([[:ITEM, "pull", location], false])

    assert location.nil?
    refute nil.equal?(location)
    assert_equal "pull", parser.do_parse
    assert_operator parser.generic_shifts, :>, 0
    assert_operator parser.generic_reductions, :>, 0
    assert_result_span(parser, location)
  end

  def test_deceptive_push_location_cannot_hide_from_the_fast_path_gate
    location = deceptive_location(line: 3)
    parser = ActionlessProbe.new

    assert_equal :need_more, parser.push(:ITEM, "push", location)
    assert_operator parser.generic_shifts, :>, 0
    assert_equal "push", parser.finish
    assert_operator parser.generic_reductions, :>, 0
    assert_result_span(parser, location)
  end

  def test_deceptive_finish_location_builds_the_generic_empty_reduction_span
    location = deceptive_location(line: 4)
    push = EmptyProbe.new

    assert_nil push.finish(location: location)
    assert_operator push.generic_reductions, :>, 0
    assert_result_span(push, location, empty: true)

    pull = EmptyProbe.new([[false, nil, location]])
    assert_nil pull.do_parse
    assert_operator pull.generic_reductions, :>, 0
    assert_result_span(pull, location, empty: true)
  end

  def test_observer_after_deceptive_location_shift_receives_the_reduction_span
    location = deceptive_location(line: 5)
    parser = ActionlessProbe.new
    events = []

    assert_equal :need_more, parser.push(:ITEM, "observed", location)
    parser.observe { |event| events << event }
    assert_equal "observed", parser.finish

    assert_equal %i[reduce accept], events.map(&:type)
    assert_equal(
      {
        "file" => "deceptive.txt",
        "line" => 5,
        "column" => 2,
        "end_line" => 5,
        "end_column" => 7
      },
      events.first.data.fetch("location")
    )
    assert_result_span(parser, location)
  end

  def test_push_observer_disables_the_active_session
    observed = ActionlessProbe.new
    assert_equal :need_more, observed.push(:ITEM, "observed")
    events = []
    observed.observe { |event| events << event.type }
    assert_equal "observed", observed.finish
    assert_operator observed.generic_reductions, :>, 0
    assert_equal %i[reduce accept], events

    removed = ActionlessProbe.new
    assert_equal :need_more, removed.push(:ITEM, "removed")
    subscription = removed.observe { |_event| flunk "removed observer ran" }
    assert removed.unobserve(subscription)
    assert_equal "removed", removed.finish
    assert_operator removed.generic_reductions, :>, 0
  end

  def test_push_debug_disables_the_active_session
    debug = ActionlessProbe.new
    assert_equal :need_more, debug.push(:ITEM, "debug")
    debug_output = StringIO.new
    debug.yydebug_output = debug_output
    debug.yydebug = true
    assert_equal "debug", debug.finish
    assert_operator debug.generic_reductions, :>, 0
    assert_includes debug_output.string, "reduce"

    assigned_false = ActionlessProbe.new
    assert_equal :need_more, assigned_false.push(:ITEM, "false")
    assigned_false.yydebug = false
    assert_equal "false", assigned_false.finish
    assert_operator assigned_false.generic_reductions, :>, 0
  end

  def test_push_jsonl_attachment_disables_the_active_session
    traced = ActionlessProbe.new
    assert_equal :need_more, traced.push(:ITEM, "traced")
    output = StringIO.new
    Ibex::Runtime::JSONLTracer.attach(traced, io: output)
    assert_equal "traced", traced.finish
    assert_operator traced.generic_reductions, :>, 0
    assert_equal ["reduce"], trace_event_names(output)
  end

  def test_observer_installed_by_next_token_is_honored_before_shift
    observer = ActionlessProbe.new([[:ITEM, "observer"], false])
    observer_events = []
    original_observer_lexer = observer.method(:next_token)
    observer.define_singleton_method(:next_token) do
      observe { |event| observer_events << event.type } if observer_events.empty?
      original_observer_lexer.call
    end
    assert_equal "observer", observer.do_parse
    assert_operator observer.generic_shifts, :>, 0
    assert_includes observer_events, :shift
  end

  def test_debug_installed_by_next_token_is_honored_before_shift
    debug = ActionlessProbe.new([[:ITEM, "debug"], false])
    debug_output = StringIO.new
    original_debug_lexer = debug.method(:next_token)
    debug.define_singleton_method(:next_token) do
      self.yydebug_output = debug_output
      self.yydebug = true
      original_debug_lexer.call
    end
    assert_equal "debug", debug.do_parse
    assert_operator debug.generic_shifts, :>, 0
    assert_includes debug_output.string, "shift"
  end

  def test_jsonl_tracer_installed_by_next_token_is_honored_before_shift
    traced = ActionlessProbe.new([[:ITEM, "trace"], false])
    trace_output = StringIO.new
    original_trace_lexer = traced.method(:next_token)
    traced.define_singleton_method(:next_token) do
      Ibex::Runtime::JSONLTracer.attach(self, io: trace_output) if trace_output.string.empty?
      original_trace_lexer.call
    end
    assert_equal "trace", traced.do_parse
    assert_operator traced.generic_shifts, :>, 0
    assert_equal %w[shift reduce], trace_event_names(trace_output)
  end

  def test_token_display_side_effect_runs_before_pull_and_push_shifts
    pull = TokenDisplayProbe.new([[:ITEM, "pull"], false])
    pull_events = install_observer_from_item_display(pull)

    assert_equal "pull", pull.do_parse
    assert_equal :shift, pull_events.first.type
    assert_equal "read:ITEM", pull_events.first.data.fetch("token")

    push = TokenDisplayProbe.new
    push_events = install_observer_from_item_display(push)

    assert_equal :need_more, push.push(:ITEM, "push")
    assert_equal :shift, push_events.first.type
    assert_equal "read:ITEM", push_events.first.data.fetch("token")
    assert_equal "push", push.finish
  end

  def test_instrumentation_installed_by_an_action_disables_later_actionless_reductions
    parser = ActionInstrumentationProbe.new([[:ITEM, 7], false])
    events = []
    parser.instrumentation = ->(active) { active.observe { |event| events << event.type } }

    assert_equal 7, parser.do_parse
    assert_equal 2, parser.generic_reductions
    assert_equal 2, parser.location_builds
    assert_equal %i[reduce accept], events
  end

  def test_observer_installed_by_semantic_error_action_gets_the_exact_lookahead_display
    parser = ActionInstrumentationProbe.new([[:ITEM, 7], false])
    events = []
    parser.instrumentation = lambda do |active|
      active.observe { |event| events << event }
      active.yyerror
    end

    assert_nil parser.do_parse
    assert_equal %i[error reject], events.map(&:type)
    assert_equal "$eof", events.first.data.fetch("token")
    assert_equal "semantic", events.first.data.fetch("reason")
  end

  def test_overridden_token_display_is_cached_before_action_phase_changes
    parser = TokenDisplayProbe.new([[:ITEM, 7], false])
    events = []
    parser.instrumentation = lambda do |active|
      active.display_phase = :error
      active.observe { |event| events << event }
      active.yyerror
    end

    assert_nil parser.do_parse
    assert_equal %i[error reject], events.map(&:type)
    assert_equal "read:$eof", events.first.data.fetch("token")
  end

  def test_yyaccept_from_pull_lexer_and_between_push_calls_uses_generic_early_accept
    pull = ControlProbe.new([[:ITEM, "pull"], false])
    pull.before_token = :yyaccept.to_proc

    assert_equal "pull", pull.do_parse
    assert_equal 0, pull.transform_calls

    push = ControlProbe.new
    assert_equal :need_more, push.push(:ITEM, "push")
    push.yyaccept
    assert_equal "push", push.finish
    assert_equal 0, push.transform_calls
  end

  def test_yyerror_from_pull_lexer_and_between_push_calls_precedes_later_actions
    pull = ControlProbe.new([[:ITEM, "pull"], false])
    pull.before_token = :yyerror.to_proc

    assert_nil pull.do_parse
    assert_equal 0, pull.transform_calls

    push = ControlProbe.new
    assert_equal :need_more, push.push(:ITEM, "push")
    push.yyerror
    assert_nil push.finish
    assert_equal 0, push.transform_calls
  end

  def test_overridden_yyaccept_matches_forced_generic_at_pull_and_push_boundaries
    expected_pull = run_pull_control(ForcedGenericOverriddenControlProbe, :yyaccept, "pull")
    expected_push = run_push_control(ForcedGenericOverriddenControlProbe, :yyaccept, "push")

    assert_equal expected_pull, run_pull_control(OverriddenControlProbe, :yyaccept, "pull")
    assert_equal expected_push, run_push_control(OverriddenControlProbe, :yyaccept, "push")
    assert_equal ["pull", 0], expected_pull
    assert_equal ["push", 0], expected_push
  end

  def test_overridden_yyerror_matches_forced_generic_at_pull_and_push_boundaries
    expected_pull = run_pull_control(ForcedGenericOverriddenControlProbe, :yyerror, "pull")
    expected_push = run_push_control(ForcedGenericOverriddenControlProbe, :yyerror, "push")

    assert_equal expected_pull, run_pull_control(OverriddenControlProbe, :yyerror, "pull")
    assert_equal expected_push, run_push_control(OverriddenControlProbe, :yyerror, "push")
    assert_equal [nil, 0], expected_pull
    assert_equal [nil, 0], expected_push
  end

  def test_direct_hook_changes_between_push_calls_are_rechecked
    parser = ActionlessProbe.new
    calls = []
    assert_equal :need_more, parser.push(:ITEM, 8)
    parser.define_singleton_method(:on_reduce) { |*payload| calls << payload }

    assert_equal 8, parser.finish
    assert_operator parser.generic_reductions, :>, 0
    refute_empty calls
  end

  def test_error_and_recovery_paths_materialize_display_and_remain_generic
    parser = ActionlessProbe.new([[:BAD, "bad"]])
    error_payloads = []
    parser.define_singleton_method(:on_error) do |token_id, value, stack|
      error_payloads << [token_to_str(token_id), value, stack]
    end

    assert_nil parser.do_parse
    assert_equal [[":BAD", "bad", []]], error_payloads
    assert_operator parser.token_display_calls, :>, 0

    recovering_class = Class.new(RuntimeParserTest::RecoveringStatements) do
      attr_reader :fast_path_at_error

      def on_error(...)
        @fast_path_at_error = instance_variable_get(:@runtime_fast_path)
        super
      end
    end
    recovering = recovering_class.new([[:BAD, "bad"], [";", nil]])
    assert_equal [:error], recovering.do_parse
    assert_equal [":BAD"], recovering.errors
    assert_equal 1, recovering.error_observations.length
    refute recovering.fast_path_at_error
  end

  private

  def run_pull_control(parser_class, control, value)
    parser = parser_class.new([[:ITEM, value], false])
    parser.before_token = control.to_proc
    [parser.do_parse, parser.transform_calls]
  end

  def run_push_control(parser_class, control, value)
    parser = parser_class.new
    parser.push(:ITEM, value)
    parser.public_send(control)
    [parser.finish, parser.transform_calls]
  end

  def deceptive_location(line:)
    DeceptiveLocation.new(
      file: "deceptive.txt", line: line, column: 2,
      end_line: line, end_column: 7
    )
  end

  def assert_result_span(parser, location, empty: false)
    span = parser.result_location
    assert_instance_of Ibex::Runtime::LocationSpan, span
    assert_same location, span.start
    assert_same location, span.finish
    assert_equal empty, span.empty?
  end

  def install_observer_from_item_display(parser)
    events = []
    attached = false
    parser.display_effect = lambda do |active, token_id|
      next unless token_id == 2 && !attached

      attached = true
      active.observe { |event| events << event }
    end
    events
  end

  def trace_event_names(output)
    output.string.lines.map { |line| JSON.parse(line).fetch("event") }
  end
end
# rubocop:enable Metrics/ClassLength
