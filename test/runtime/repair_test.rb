# frozen_string_literal: true

require_relative "parser_test"

class RuntimeRepairTest < Minitest::Test
  def test_policy_is_explicit_immutable_and_validated
    policy = Ibex::Runtime::RepairPolicy.new

    assert_predicate policy, :frozen?
    assert_equal 1, policy.insert_cost
    assert_equal 1, policy.delete_cost
    assert_equal 2, policy.replace_cost
    assert_raises(ArgumentError) { Ibex::Runtime::RepairPolicy.new(max_cost: 0) }
    assert_raises(ArgumentError) { Ibex::Runtime::RepairPolicy.new(success_shifts: 4, max_lookahead: 3) }

    parser = RuntimeParserTest::Calculator.new([])
    assert_nil parser.repair_policy
    assert_raises(ArgumentError) { parser.repair_policy = Object.new }
    assert_nil parser.repair_policy = nil
  end

  def test_default_behavior_does_not_search_or_prefetch
    reads = 0
    parser = RuntimeParserTest::Calculator.new([["+", nil], [:INT, 2]])
    parser.define_singleton_method(:next_token) do
      reads += 1
      @tokens.shift
    end

    assert_raises(Ibex::ParseError) { parser.do_parse }
    assert_equal 1, reads
  end

  def test_pull_parser_inserts_a_missing_token_and_calls_each_hook_once
    parser = RuntimeParserTest::Calculator.new([[:INT, 1], [:INT, 2]])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    errors = []
    plans = []
    shifts = []
    parser.define_singleton_method(:on_error) { |*payload| errors << payload }
    parser.define_singleton_method(:on_repair) { |plan| plans << plan }
    parser.define_singleton_method(:on_shift) { |*payload| shifts << payload }

    assert_equal 3, parser.do_parse
    assert_equal 1, errors.length
    assert_equal 1, plans.length
    plan = plans.first
    assert_predicate plan, :frozen?
    assert_equal 1, plan.cost
    assert_equal [{ kind: :insert, position: 0, token_id: 3, token_name: "+", cost: 1 }],
                 plan.edits.map(&:to_h)
    assert_includes shifts, [3, nil, 5]
  end

  def test_dormant_repair_debug_does_not_construct_or_dispatch_trace_payloads
    parser = RuntimeParserTest::Calculator.new([[:INT, 1], [:INT, 2]])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    trace_calls = 0
    parser.define_singleton_method(:trace) { |_message| trace_calls += 1 }

    assert_equal 3, parser.do_parse
    assert_equal 0, trace_calls
  end

  def test_equal_cost_prefers_deleting_an_extra_token_over_inventing_a_value
    parser = RuntimeParserTest::Calculator.new([[:INT, 1], ["+", nil], ["+", nil], [:INT, 2]])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    plans = observe_repair(parser)

    assert_equal 3, parser.do_parse
    assert_equal :delete, plans.first.edits.first.kind
    assert_equal "+", plans.first.edits.first.token_name
  end

  def test_replacement_preserves_the_original_value_and_location
    location = { file: "repair.y", line: 2, column: 4 }
    parser = RuntimeParserTest::Calculator.new([["+", 7, location]])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new(
      insert_cost: 5, delete_cost: 5, replace_cost: 1, max_cost: 1
    )
    plans = observe_repair(parser)

    assert_equal 7, parser.do_parse
    edit = plans.first.edits.first
    assert_equal :replace, edit.kind
    assert_equal "INT", edit.token_name
  end

  def test_push_parser_buffers_until_eof_proves_the_repair
    parser = RuntimeParserTest::Calculator.new([])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    errors = []
    plans = []
    parser.define_singleton_method(:on_error) { |*payload| errors << payload }
    parser.define_singleton_method(:on_repair) { |plan| plans << plan }

    assert_equal :need_more, parser.push(:INT, 1)
    assert_equal :need_more, parser.push(:INT, 2)
    assert_empty errors
    assert_empty plans
    assert_equal 3, parser.finish
    assert_equal 1, errors.length
    assert_equal 1, plans.length
    assert_equal :insert, plans.first.edits.first.kind
  end

  def test_policy_cannot_change_during_an_active_push_session
    parser = RuntimeParserTest::Calculator.new([])
    assert_equal :need_more, parser.push(:INT, 1)

    error = assert_raises(Ibex::ParseError) do
      parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    end
    assert_includes error.message, "active push session"
  end

  def test_failed_or_budget_exhausted_search_falls_back_without_second_error
    policies = [
      Ibex::Runtime::RepairPolicy.new(insert_cost: 2, delete_cost: 2, replace_cost: 2, max_cost: 1),
      Ibex::Runtime::RepairPolicy.new(max_configurations: 1)
    ]
    policies.each do |policy|
      parser = RuntimeParserTest::Calculator.new([["+", nil]])
      parser.repair_policy = policy
      errors = []
      repairs = []
      parser.define_singleton_method(:on_error) { |*payload| errors << payload }
      parser.define_singleton_method(:on_repair) { |plan| repairs << plan }

      assert_nil parser.do_parse
      assert_equal 1, errors.length
      assert_empty repairs
    end
  end

  def test_default_error_handler_still_raises_when_no_plan_is_available
    parser = RuntimeParserTest::Calculator.new([["+", nil]])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new(
      insert_cost: 2, delete_cost: 2, replace_cost: 2, max_cost: 1
    )

    error = assert_raises(Ibex::ParseError) { parser.do_parse }
    assert_includes error.message, "unexpected +"
  end

  def test_repair_uses_normal_actions_and_emits_no_synthetic_recovery_event
    parser = RuntimeParserTest::Calculator.new([[:INT, 1], [:INT, 2]])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    parser.define_singleton_method(:on_error) { |*| nil }
    events = []
    parser.observe { |event| events << event.type }

    assert_equal 3, parser.do_parse
    assert_equal 1, events.count(:error)
    assert_includes events, :shift
    assert_includes events, :reduce
    assert_equal :accept, events.last
    refute_includes events, :recover
    refute_includes events, :reject
  end

  def test_hook_failures_propagate_before_edited_tokens_are_applied
    %i[on_error on_repair].each do |hook|
      parser = RuntimeParserTest::Calculator.new([[:INT, 1], [:INT, 2]])
      parser.repair_policy = Ibex::Runtime::RepairPolicy.new
      parser.define_singleton_method(:on_error) { |*| nil } unless hook == :on_error
      parser.define_singleton_method(hook) { |*| raise "#{hook} failed" }

      error = assert_raises(RuntimeError) { parser.do_parse }
      assert_equal "#{hook} failed", error.message
    end
  end

  def test_unknown_token_can_be_deleted_without_losing_its_diagnostic_name
    parser = RuntimeParserTest::Calculator.new([[:INT, 1], [:BAD, "bad"]])
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new
    errors = []
    plans = []
    parser.define_singleton_method(:on_error) { |token_id, _value, _stack| errors << parser.token_to_str(token_id) }
    parser.define_singleton_method(:on_repair) { |plan| plans << plan }

    assert_equal 1, parser.do_parse
    assert_equal [":BAD"], errors
    assert_equal :delete, plans.first.edits.first.kind
    assert_equal ":BAD", plans.first.edits.first.token_name
  end

  private

  def observe_repair(parser)
    plans = []
    parser.define_singleton_method(:on_error) { |*| nil }
    parser.define_singleton_method(:on_repair) { |plan| plans << plan }
    plans
  end
end
