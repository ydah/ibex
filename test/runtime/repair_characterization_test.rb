# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/runtime/repair_search"

class RuntimeRepairCharacterizationTest < Minitest::Test
  Configuration = Ibex::Runtime::RepairSearch::Configuration

  def test_priority_tuple_closes_equal_cost_selection
    search = repair_search([], complete: true)
    punctuation = edit(:delete, token_id: 3, token_name: "+")
    word = edit(:insert, token_id: 2, token_name: "INT")
    replacement = edit(:replace, token_id: 2, token_name: "INT")

    assert_equal [1, 0, [[0, 0, 3]], 1, 0, 0, [0]], priority(search, punctuation)
    assert_equal [1, 1, [[0, 1, 2]], 1, 0, 0, [0]], priority(search, word)
    assert_equal [1, 1, [[0, 2, 2]], 1, 0, 0, [0]], priority(search, replacement)
    assert_equal(-1, priority(search, punctuation) <=> priority(search, word))
    assert_equal(-1, priority(search, word) <=> priority(search, replacement))
  end

  def test_goal_shift_progress_and_stack_complete_the_priority_order
    search = repair_search([], complete: true)
    edit = edit(:insert, token_id: 3, token_name: "+")
    baseline = configuration(edit)

    assert_equal(-1, priority(search, configuration(edit, goal: true)) <=> priority(search, baseline))
    assert_equal(-1, priority(search, configuration(edit, shifts: 2)) <=> priority(search, baseline))
    assert_equal 1, priority(search, configuration(edit, input_index: 2)) <=> priority(search, baseline)
    assert_equal 1, priority(search, configuration(edit, stack: [0, 1])) <=> priority(search, baseline)
  end

  def test_incomplete_input_is_distinct_but_exhaustion_and_no_plan_share_nil
    invalid = repair_input(3, "+")
    incomplete = repair_search([invalid], complete: false).search([0])
    exhausted = repair_search(
      [invalid], complete: true,
                 policy: Ibex::Runtime::RepairPolicy.new(max_configurations: 1)
    ).search([0])
    no_plan = repair_search(
      [invalid], complete: true,
                 policy: Ibex::Runtime::RepairPolicy.new(
                   insert_cost: 2, delete_cost: 2, replace_cost: 2, max_cost: 1
                 )
    ).search([0])

    assert_same Ibex::Runtime::RepairSearch::NEED_INPUT, incomplete
    assert_nil exhausted
    assert_nil no_plan
  end

  def test_typed_search_result_preserves_every_bounded_outcome
    invalid = repair_input(3, "+")
    incomplete = repair_search([invalid], complete: false).search_result([0])
    exhausted = repair_search(
      [invalid], complete: true,
                 policy: Ibex::Runtime::RepairPolicy.new(max_configurations: 1)
    ).search_result([0])
    no_plan = repair_search(
      [invalid], complete: true,
                 policy: Ibex::Runtime::RepairPolicy.new(
                   insert_cost: 2, delete_cost: 2, replace_cost: 2, max_cost: 1
                 )
    ).search_result([0])

    assert_equal :need_input, incomplete.status
    assert_equal :exhausted, exhausted.status
    assert_equal :not_found, no_plan.status
    [incomplete, exhausted, no_plan].each do |result|
      assert_nil result.plan
      assert_kind_of Integer, result.configurations
      assert_predicate result, :frozen?
    end
  end

  private

  def parser_tables
    {
      actions: [[nil, nil, [:shift, 1], nil], [[:accept]]],
      gotos: [[], []],
      default_actions: [],
      productions: [],
      token_names: { 0 => "$end", 1 => "error", 2 => "INT", 3 => "+" }
    }
  end

  def repair_search(tokens, complete:, policy: Ibex::Runtime::RepairPolicy.new)
    Ibex::Runtime::RepairSearch.new(parser_tables, policy, tokens, complete: complete)
  end

  def repair_input(token_id, token_name)
    Ibex::Runtime::RepairInput.new(token_id: token_id, token_name: token_name, value: nil, location: nil)
  end

  def edit(kind, token_id:, token_name:)
    Ibex::Runtime::RepairEdit.new(kind: kind, position: 0, token_id: token_id, token_name: token_name, cost: 1)
  end

  def configuration(edit, stack: [0], input_index: 0, shifts: 0, goal: false)
    Configuration.new(
      stack: stack, input_index: input_index, shifts: shifts, cost: 1, edits: [edit], goal: goal
    )
  end

  def priority(search, edit_or_configuration)
    value = if edit_or_configuration.is_a?(Configuration)
              edit_or_configuration
            else
              configuration(edit_or_configuration)
            end
    search.__send__(:priority_for, value)
  end
end
