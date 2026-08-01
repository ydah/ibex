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

  def test_ten_distinct_reachable_table_faults_are_all_detected
    grammar = normalize("class Pair\nrule\nstart: A B\nend\n")
    automata = Ibex::Fuzz::ALGORITHMS.to_h do |algorithm|
      [algorithm, Ibex::LALR::Builder.new(grammar, algorithm: algorithm).build]
    end
    reference = automata.fetch(:slr)
    trace = Ibex::TableSimulation::Simulator.new(reference).simulate(%w[A B]).steps
    faults = injected_faults(reference, trace)

    assert_equal 10, faults.length
    faults.each do |name, fault|
      corrupted = automata.merge(slr: fault)
      error = assert_raises(Ibex::Fuzz::Mismatch, name.to_s) do
        Ibex::Fuzz.new(grammar, count: 1, automata: corrupted).run
      end
      assert_equal :generated, error.details.fetch(:kind), name.to_s
    end
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "fuzz.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def injected_faults(automaton, trace)
    shift = trace.find { |step| step.action == "shift" } || raise("missing reachable shift")
    reduce = trace.find { |step| step.action == "reduce" } || raise("missing reachable reduce")
    accept = trace.find { |step| step.action == "accept" } || raise("missing reachable accept")
    production = automaton.grammar.productions.fetch(reduce.production_id)
    goto_state = trace_state_before_reduction(trace, reduce)

    {
      shift_action_deleted: remove_action(automaton, shift),
      shift_retyped_as_error: replace_action(automaton, shift, type: :error),
      shift_target_redirected: replace_action(automaton, shift, type: :shift, state: shift.state),
      reduce_action_deleted: remove_action(automaton, reduce),
      reduce_retyped_as_error: replace_action(automaton, reduce, type: :error),
      reduce_retyped_as_shift: replace_action(automaton, reduce, type: :shift, state: 0),
      goto_deleted: replace_goto(automaton, goto_state, production.lhs, nil),
      goto_target_redirected: replace_goto(automaton, goto_state, production.lhs, 0),
      accept_action_deleted: remove_action(automaton, accept),
      accept_retyped_as_error: replace_action(automaton, accept, type: :error)
    }.freeze
  end

  def trace_state_before_reduction(trace, reduction)
    stack = [0]
    trace.each do |step|
      return stack.fetch(-(reduction.rhs_length + 1)) if step.equal?(reduction)

      stack << step.target_state if step.action == "shift"
      next unless step.action == "reduce"

      stack.pop(step.rhs_length)
      stack << step.target_state
    end
    raise "reduction is not in trace"
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

  def replace_goto(automaton, state_id, symbol_id, target)
    replace_state(automaton, state_id) do |state|
      gotos = state.gotos.reject { |id, _state| id == symbol_id }
      gotos = gotos.merge(symbol_id => target) if target
      [state.actions, gotos]
    end
  end

  def replace_state(automaton, state_id)
    states = automaton.states.map do |state|
      next state unless state.id == state_id

      replacement = yield(state)
      actions, gotos = replacement.is_a?(Array) ? replacement : [replacement, state.gotos]
      Ibex::IR::AutomatonState.new(
        id: state.id, items: state.items, transitions: state.transitions,
        actions: actions, gotos: gotos, default_action: state.default_action,
        conflicts: state.conflicts
      )
    end
    Ibex::IR::Automaton.new(
      grammar: automaton.grammar, states: states, conflict_summary: automaton.conflict_summary,
      algorithm: automaton.algorithm, entry_states: automaton.entry_states
    )
  end
end
