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

  class ValuesActionProbe < ActionlessProbe
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
      productions: [
        { lhs: 3, length: 1, action: :_ibex_action_0, values_action: true } # rubocop:disable Naming/VariableNumber
      ]
    }.freeze

    attr_reader :action_calls, :action_semantic_locations
    attr_writer :action_effect

    def self.parser_tables = TABLES

    def initialize(...)
      super
      @action_calls = 0
    end

    private

    def _ibex_action_0(values) # rubocop:disable Naming/VariableNumber
      @action_calls += 1
      @action_semantic_locations = instance_variable_get(:@semantic_locations)
      @action_effect&.call(self, values)
      values.first
    end
  end

  class CompactActionlessProbe < ActionlessProbe
    TABLES = Ractor.make_shareable(
      ActionlessProbe::TABLES.merge(
        compact_fast_driver: true,
        compact_default_actions: [],
        actions: Ibex::Tables::CompactActions.build(ActionlessProbe::TABLES.fetch(:actions)),
        gotos: Ibex::Tables::Compact.build(ActionlessProbe::TABLES.fetch(:gotos)),
        productions: Ibex::Tables::CompactProductions.build(ActionlessProbe::TABLES.fetch(:productions))
      )
    )

    attr_reader :generic_actions

    def self.parser_tables = TABLES

    def initialize(...)
      super
      @generic_actions = 0
    end

    private

    def action_for_current_state
      @generic_actions += 1
      super
    end
  end

  class CompactValuesActionProbe < ValuesActionProbe
    TABLES = Ractor.make_shareable(
      ValuesActionProbe::TABLES.merge(
        compact_fast_driver: true,
        compact_default_actions: [],
        actions: Ibex::Tables::CompactActions.build(ValuesActionProbe::TABLES.fetch(:actions)),
        gotos: Ibex::Tables::Compact.build(ValuesActionProbe::TABLES.fetch(:gotos)),
        productions: Ibex::Tables::CompactProductions.build(ValuesActionProbe::TABLES.fetch(:productions))
      )
    )

    attr_reader :generic_actions

    def self.parser_tables = TABLES

    def initialize(...)
      super
      @generic_actions = 0
    end

    private

    def action_for_current_state
      @generic_actions += 1
      super
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

  class LookupCountingProbe < ActionlessProbe
    attr_reader :runtime_core_method_calls

    def initialize(...)
      super
      @runtime_core_method_calls = 0
    end

    private

    def runtime_core_method(...)
      @runtime_core_method_calls += 1
      super
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

  def test_values_only_action_uses_the_fast_reduction_without_per_reduction_locations
    first = ValuesActionProbe.new([[:ITEM, "first"], false])
    second = ValuesActionProbe.new([[:ITEM, "second"], false])

    assert_equal "first", first.do_parse
    assert_equal "second", second.do_parse
    assert_equal [1, 1], [first.action_calls, second.action_calls]
    assert_equal [0, 0], [first.generic_reductions, second.generic_reductions]
    assert_empty first.action_semantic_locations
    assert first.action_semantic_locations.frozen?
    assert_same first.action_semantic_locations, second.action_semantic_locations
  end

  def test_compact_pull_driver_commits_shift_reduce_and_accept_without_generic_dispatch
    actionless = CompactActionlessProbe.new([[:ITEM, "compact"], false])
    values_action = CompactValuesActionProbe.new([[:ITEM, "semantic"], false])

    assert_equal "compact", actionless.do_parse
    assert_equal "semantic", values_action.do_parse
    assert_equal 0, actionless.generic_actions
    assert_equal 0, values_action.generic_actions
    assert_equal 1, values_action.action_calls
  end

  def test_compact_pull_reuses_internal_scratch_stacks_between_sessions
    parser = CompactActionlessProbe.new([[:ITEM, "first"], false])

    assert_equal "first", parser.do_parse
    state_stack = parser.instance_variable_get(:@state_stack)
    value_stack = parser.instance_variable_get(:@value_stack)
    cst_errors = parser.instance_variable_get(:@cst_errors)
    parser.instance_variable_get(:@tokens).push([:ITEM, "second"], false)

    assert_equal "second", parser.do_parse
    assert_same state_stack, parser.instance_variable_get(:@state_stack)
    assert_same value_stack, parser.instance_variable_get(:@value_stack)
    assert_same cst_errors, parser.instance_variable_get(:@cst_errors)
  end

  def test_compact_pull_driver_falls_back_before_an_unknown_token
    parser = CompactActionlessProbe.new([[:UNKNOWN, "bad"], false])

    error = assert_raises(Ibex::ParseError) { parser.do_parse }

    assert_equal "bad", error.token_value
    assert_operator parser.generic_actions, :>, 0
    assert_equal [0, 0], [parser.generic_shifts, parser.generic_reductions]
  end

  def test_compact_values_action_preserves_dynamic_hook_boundary
    parser = CompactValuesActionProbe.new([%i[ITEM original], false])
    hooks = []
    parser.action_effect = lambda do |active, values|
      active.define_singleton_method(:on_reduce) { |*payload| hooks << payload }
      values[0] = :changed
    end

    assert_equal :changed, parser.do_parse
    assert_equal [[0, [:original], :changed]], hooks
    assert_equal 1, parser.generic_actions
  end

  def test_values_only_action_preserves_pre_action_hook_values_and_location_hook_shape
    parser = ValuesActionProbe.new([%i[ITEM original], false])
    value_hooks = []
    location_hooks = []
    parser.action_effect = lambda do |active, values|
      active.define_singleton_method(:on_reduce) { |*payload| value_hooks << payload }
      active.define_singleton_method(:on_reduce_location) { |*payload| location_hooks << payload }
      values[0] = :changed
    end

    assert_equal :changed, parser.do_parse
    assert_equal [[0, [:original], :changed]], value_hooks
    assert_equal [[0, [:original], :changed, [nil], nil]], location_hooks
    assert_equal 0, parser.generic_reductions
  end

  def test_values_only_action_honors_debug_and_observer_installed_during_the_action
    parser = ValuesActionProbe.new([%i[ITEM value], false])
    events = []
    output = StringIO.new
    parser.action_effect = lambda do |active, _values|
      active.observe { |event| events << event.type }
      active.yydebug_output = output
      active.yydebug = true
    end

    assert_equal :value, parser.do_parse
    assert_equal [:accept], events
    assert_includes output.string, "reduce 0"
    assert_equal 0, parser.generic_reductions
  end

  def test_values_only_action_honors_semantic_accept_and_error
    accepted = ValuesActionProbe.new([%i[ITEM accepted], false])
    accepted.action_effect = ->(active, _values) { active.yyaccept }
    assert_equal :accepted, accepted.do_parse
    assert_equal 0, accepted.generic_reductions

    rejected = ValuesActionProbe.new([%i[ITEM rejected], false])
    rejected.action_effect = ->(active, _values) { active.yyerror }
    assert_nil rejected.do_parse
    assert_equal 0, rejected.generic_reductions
  end

  def test_nil_debug_flag_is_eligible_because_debug_checks_use_truthiness
    parser = ValuesActionProbe.new([%i[ITEM value], false])
    parser.yydebug = nil

    assert_equal :value, parser.do_parse
    assert_equal [0, 0], [parser.generic_shifts, parser.generic_reductions]
  end

  def test_application_method_helper_is_not_used_for_eligibility_introspection
    parser = MethodOverrideProbe.new([[:ITEM, 9], false])

    assert_equal 9, parser.do_parse
    assert_empty parser.method_helper_calls
    assert_equal [0, 0], [parser.generic_shifts, parser.generic_reductions]
  end

  def test_repeated_callback_refresh_does_not_rebuild_effective_methods
    parser = LookupCountingProbe.new
    assert_equal :need_more, parser.push(:ITEM, 10)
    construction_calls = parser.runtime_core_method_calls

    1_000.times { parser.send(:refresh_runtime_fast_path_after_user_code!) }

    assert_equal construction_calls, parser.runtime_core_method_calls
    assert parser.fast_path_active?
    assert_equal 10, parser.finish
  end

  def test_class_hook_change_invalidates_cached_eligibility
    parser_class = Class.new(CompactActionlessProbe)
    first = parser_class.new([[:ITEM, 10], false])

    assert_equal 10, first.do_parse
    assert first.send(:runtime_fast_path_class_hooks_eligible?)

    parser_class.define_method(:on_reduce) { |*| @class_hook_called = true }
    second = parser_class.new([[:ITEM, 11], false])

    assert_equal 11, second.do_parse
    assert second.instance_variable_get(:@class_hook_called)
    assert_operator second.generic_reductions, :>, 0
  end

  def test_undefining_relevant_singleton_hook_disables_active_fast_path
    parser = ActionlessProbe.new
    assert_equal :need_more, parser.push(:ITEM, 11)
    assert parser.fast_path_active?

    parser.singleton_class.send(:undef_method, :on_reduce)

    refute parser.fast_path_active?
    assert_raises(NoMethodError) { parser.finish }
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

  def test_replacing_all_singleton_mutation_callbacks_cannot_hide_a_hook
    parser = ActionlessProbe.new
    assert_equal :need_more, parser.push(:ITEM, 12)
    assert parser.fast_path_active?

    %i[singleton_method_added singleton_method_removed singleton_method_undefined].each do |callback|
      parser.define_singleton_method(callback) { |_name| nil }
    end
    assert parser.fast_path_active?

    hook_calls = []
    parser.define_singleton_method(:on_reduce) { |*payload| hook_calls << payload }

    refute parser.fast_path_active?
    assert_equal 12, parser.finish
    refute_empty hook_calls
    assert_operator parser.generic_reductions, :>, 0
  end

  def test_preexisting_singleton_mutation_callbacks_are_guarded_by_the_tracker
    callback_class = Class.new(ActionlessProbe) do
      private

      %i[singleton_method_added singleton_method_removed singleton_method_undefined].each do |callback|
        define_method(callback) { |_name| nil }
      end
    end
    parser = callback_class.new
    assert_equal :need_more, parser.push(:ITEM, 18)
    assert parser.fast_path_active?

    parser.define_singleton_method(:on_reduce) { |*| nil }

    refute parser.fast_path_active?
    assert_equal 18, parser.finish
    assert_operator parser.generic_reductions, :>, 0
  end

  def test_tracker_remains_installed_across_push_sessions
    parser = ActionlessProbe.new
    assert_equal :need_more, parser.push(:ITEM, 13)
    assert_equal 13, parser.finish
    parser.reset_push

    assert_equal :need_more, parser.push(:ITEM, 14)
    assert parser.fast_path_active?
    assert_equal 14, parser.finish
    assert_equal [0, 0], [parser.generic_shifts, parser.generic_reductions]
  end

  def test_idle_prepend_above_the_tracker_disqualifies_the_next_session
    parser = ActionlessProbe.new
    assert_equal :need_more, parser.push(:ITEM, 16)
    assert_equal 16, parser.finish
    parser.reset_push

    callback_layer = Module.new do
      private

      define_method(:singleton_method_added) { |_name| nil }
    end
    parser.singleton_class.prepend(callback_layer)

    assert_equal :need_more, parser.push(:ITEM, 17)
    refute parser.fast_path_active?
    hook_calls = []
    parser.define_singleton_method(:on_reduce) { |*payload| hook_calls << payload }
    assert_equal 17, parser.finish
    refute_empty hook_calls
    assert_operator parser.generic_shifts, :>, 0
    assert_operator parser.generic_reductions, :>, 0
  end

  def test_frozen_singleton_class_falls_back_to_the_generic_driver
    parser = ActionlessProbe.new([[:ITEM, 15], false])
    parser.singleton_class.freeze

    assert_equal 15, parser.do_parse
    assert_operator parser.generic_shifts, :>, 0
    assert_operator parser.generic_reductions, :>, 0
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
    pull = CompactActionlessProbe.new([[:ITEM, "pull", location], false])
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
    parser = CompactActionlessProbe.new([[:ITEM, "pull", location], false])

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

  def test_observation_invalidation_bypasses_application_disable_helpers
    subclass = Class.new(ActionlessProbe) do
      private

      def disable_runtime_fast_path! = raise("application helper must not run")
    end

    [subclass.new, ActionlessProbe.new].each_with_index do |parser, index|
      assert_equal :need_more, parser.push(:ITEM, index)
      if index == 1
        parser.define_singleton_method(:disable_runtime_fast_path!) do
          raise "application singleton helper must not run"
        end
      end

      events = []
      parser.observe { |event| events << event.type }
      assert_equal index, parser.finish
      assert_operator parser.generic_reductions, :>, 0
      assert_equal %i[reduce accept], events
    end
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
    traced.define_singleton_method(:disable_runtime_fast_path!) do
      raise "application singleton helper must not run"
    end
    output = StringIO.new
    Ibex::Runtime::JSONLTracer.attach(traced, io: output)
    assert_equal "traced", traced.finish
    assert_operator traced.generic_reductions, :>, 0
    assert_equal ["reduce"], trace_event_names(output)
  end

  def test_observer_installed_by_next_token_is_honored_before_shift
    observer = CompactActionlessProbe.new([[:ITEM, "observer"], false])
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
    debug = CompactActionlessProbe.new([[:ITEM, "debug"], false])
    debug_output = StringIO.new
    original_debug_lexer = debug.method(:next_token)
    debug.define_singleton_method(:yydebug=) { |enabled| @yydebug = enabled }
    debug.define_singleton_method(:next_token) do
      self.yydebug_output = debug_output
      self.yydebug = true
      original_debug_lexer.call
    end
    assert_equal "debug", debug.do_parse
    assert_operator debug.generic_shifts, :>, 0
    assert_includes debug_output.string, "shift"
  end

  def test_direct_scalar_changes_from_user_code_disable_later_fast_reductions
    {
      runtime_observers: {},
      repair_policy: Object.new,
      location_stack: []
    }.each do |name, value|
      parser = ActionInstrumentationProbe.new([[:ITEM, name], false])
      parser.instrumentation = ->(active) { active.instance_variable_set(:"@#{name}", value) }

      assert_equal name, parser.do_parse
      assert_equal 2, parser.generic_reductions
      refute parser.fast_path_active?
    end
  end

  def test_jsonl_tracer_installed_by_next_token_is_honored_before_shift
    traced = CompactActionlessProbe.new([[:ITEM, "trace"], false])
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
