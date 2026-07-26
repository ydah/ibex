# frozen_string_literal: true

require_relative "test_helper"

class TableSimulationTest < Minitest::Test
  def test_simulates_shifts_reductions_and_accept_without_semantic_actions
    source = <<~GRAMMAR
      class SimulationParser
      token NUMBER PLUS
      rule
      start: expression { raise "must not execute" }
      expression: expression PLUS NUMBER { raise "must not execute" }
                | NUMBER { raise "must not execute" }
      end
    GRAMMAR
    automaton = automaton_for(source)
    result = Ibex::TableSimulation::Simulator.new(automaton).simulate(%w[NUMBER PLUS NUMBER])

    assert_equal :accepted, result.status
    assert_equal %w[shift reduce shift shift reduce reduce accept], result.steps.map(&:action)
    assert_equal [2, 1, 0], result.steps.filter_map(&:production_id)
    assert_equal((1..7).to_a, result.steps.map(&:sequence))
    assert_equal %w[NUMBER PLUS NUMBER], result.tokens
    assert result.steps.all?(&:frozen?)
  end

  def test_explicit_error_masks_default_reduction
    simulator = Ibex::TableSimulation::Simulator.new(default_reduction_automaton)

    accepted = simulator.simulate(%w[NUMBER PLUS NUMBER])
    default_step = accepted.steps.find { |step| step.action_source == "default" }
    assert_equal "reduce", default_step.action
    assert_equal 2, default_step.production_id

    rejected = simulator.simulate(%w[NUMBER NUMBER])
    assert_equal :error, rejected.status
    assert_equal "error", rejected.steps.last.action
    assert_equal "explicit", rejected.steps.last.action_source
    used_default = rejected.steps.any? { |step| step.token == "NUMBER" && step.action_source == "default" }
    refute used_default
  end

  def test_session_accepts_one_token_at_a_time
    session = Ibex::TableSimulation::Simulator.new(fixture_automaton).start

    assert_equal ["shift"], session.push("NUMBER").map(&:action)
    assert_predicate session.steps, :frozen?
    assert_predicate session.tokens, :frozen?
    assert_equal %w[reduce shift], session.push("PLUS").map(&:action)
    assert_equal ["shift"], session.push("NUMBER").map(&:action)
    result = session.finish

    assert_equal :accepted, result.status
    assert_equal %w[reduce reduce accept], result.steps.last(3).map(&:action)
    assert_raises(Ibex::Error) { session.finish }
    assert_raises(Ibex::Error) { session.push("NUMBER") }
  end

  def test_unknown_and_reserved_terminals_and_budgets_fail_closed
    simulator = Ibex::TableSimulation::Simulator.new(fixture_automaton)
    assert_raises(Ibex::Error) { simulator.simulate(["MISSING"]) }
    assert_raises(Ibex::Error) { simulator.simulate(["$eof"]) }
    assert_raises(Ibex::Error) { simulator.simulate(["error"]) }

    steps = Ibex::TableSimulation::Simulator.new(fixture_automaton, max_steps: 1)
    error = assert_raises(Ibex::Error) { steps.simulate(["NUMBER"]) }
    assert_includes error.message, "exceeded 1 actions"

    stack = Ibex::TableSimulation::Simulator.new(fixture_automaton, max_stack: 1)
    error = assert_raises(Ibex::Error) { stack.simulate(["NUMBER"]) }
    assert_includes error.message, "stack depth 1"
  end

  def test_result_is_deterministic_and_text_includes_stack_transitions
    simulator = Ibex::TableSimulation::Simulator.new(fixture_automaton)
    first = simulator.simulate(%w[NUMBER PLUS NUMBER])
    second = simulator.simulate(%w[NUMBER PLUS NUMBER])

    assert_equal first.to_json, second.to_json
    text = Ibex::TableSimulation::Text.render(first)
    assert_includes text, "state=0 token=\"NUMBER\" action=shift target=1"
    assert_includes text, "production=2 lhs=expression rhs=1 goto=3"
    assert text.end_with?("status=accepted\n")
  end

  private

  def fixture_automaton
    @fixture_automaton ||= Ibex::IR::Validator.validate(
      File.read(File.expand_path("fixtures/ir/automaton-v2.json", __dir__))
    )
  end

  def default_reduction_automaton
    states = fixture_automaton.states.map do |state|
      next state unless state.id == 1

      Ibex::IR::AutomatonState.new(
        id: state.id,
        items: state.items,
        transitions: state.transitions,
        actions: { 1 => { type: :error }, 2 => { type: :error } },
        gotos: state.gotos,
        default_action: { type: :reduce, production: 2 },
        conflicts: state.conflicts
      )
    end
    Ibex::IR::Automaton.new(
      grammar: fixture_automaton.grammar,
      states: states,
      conflict_summary: fixture_automaton.conflict_summary,
      algorithm: fixture_automaton.algorithm,
      grammar_digest: fixture_automaton.grammar_digest,
      schema_version: fixture_automaton.schema_version
    )
  end

  def automaton_for(source)
    ast = Ibex::Frontend::Parser.new(source, file: "simulation.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    Ibex::LALR::Builder.new(grammar).build
  end
end
