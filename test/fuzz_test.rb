# frozen_string_literal: true

require_relative "test_helper"

class FuzzTest < Minitest::Test
  def test_generated_and_mutated_sentences_match_all_algorithms
    grammar = normalize(<<~GRAMMAR)
      class Lists
      rule
      start: items
      items: ITEM | ITEM ',' items
      end
    GRAMMAR

    report = Ibex::Fuzz.new(
      grammar, seed: 73, count: 20, max_tokens: 9, coverage_guided: true
    ).run

    assert_equal "no_difference_within_bounds", report.fetch(:result)
    assert_equal 20, report.fetch(:generated_sentences)
    assert_operator report.fetch(:mutated_sentences), :>=, 40
    assert_equal %w[slr lalr ielr lr1], report.fetch(:algorithms)
  end

  def test_ten_reachable_automaton_faults_are_all_detected
    grammar = normalize("class Pair\nrule\nstart: A B\nend\n")
    automata = Ibex::Fuzz::ALGORITHMS.to_h do |algorithm|
      [algorithm, Ibex::LALR::Builder.new(grammar, algorithm: algorithm).build]
    end
    reference = automata.fetch(:slr)
    trace = Ibex::TableSimulation::Simulator.new(reference).simulate(%w[A B]).steps
    faults = injected_faults(reference, trace)

    assert_equal 10, faults.length
    faults.each_with_index do |fault, index|
      corrupted = automata.merge(slr: fault)
      error = assert_raises(Ibex::Fuzz::Mismatch, "fault #{index + 1}") do
        Ibex::Fuzz.new(grammar, count: 1, automata: corrupted).run
      end
      assert_equal :generated, error.details.fetch(:kind), "fault #{index + 1}"
    end
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "fuzz.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def injected_faults(automaton, trace)
    actionable = trace.select { |step| %w[shift reduce accept].include?(step.action) }
    faults = actionable.flat_map do |step|
      [
        replace_action(automaton, step, type: :error),
        remove_action(automaton, step)
      ]
    end
    shifts = actionable.select { |step| step.action == "shift" }
    faults.concat(shifts.map { |step| replace_action(automaton, step, type: :shift, state: step.state) })
    faults.first(10)
  end

  def replace_action(automaton, step, replacement)
    replace_state(automaton, step.state) do |state|
      state.actions.merge(step.token_id => replacement)
    end
  end

  def remove_action(automaton, step)
    replace_state(automaton, step.state) do |state|
      state.actions.reject { |token_id, _action| token_id == step.token_id }
    end
  end

  def replace_state(automaton, state_id)
    states = automaton.states.map do |state|
      next state unless state.id == state_id

      Ibex::IR::AutomatonState.new(
        id: state.id, items: state.items, transitions: state.transitions,
        actions: yield(state), gotos: state.gotos, default_action: state.default_action,
        conflicts: state.conflicts
      )
    end
    Ibex::IR::Automaton.new(
      grammar: automaton.grammar, states: states, conflict_summary: automaton.conflict_summary,
      algorithm: automaton.algorithm, entry_states: automaton.entry_states
    )
  end
end
