# frozen_string_literal: true

require_relative "../test_helper"

class CounterexampleSelectionTest < Minitest::Test
  def test_searches_only_the_selected_conflict
    automaton = build(<<~GRAMMAR)
      class P
      token NUM
      expect 4
      rule
      expr: expr '+' expr
          | expr '*' expr
          | NUM
      end
    GRAMMAR
    selected_state = automaton.states.find { |state| state.conflicts.length > 1 }
    calls = []
    search = Object.new
    outcome = not_found_outcome
    search.define_singleton_method(:call) { outcome }
    factory = lambda do |_automaton, state, conflict, **_options|
      calls << [state.id, conflict[:symbol]]
      search
    end

    Ibex::LALR::ConflictSearch.stub(:new, factory) do
      result = Ibex::LALR::Counterexample.new(automaton).for_conflict(selected_state.id, 1)
      assert_equal selected_state.id, result.fetch(:state)
      assert_equal [[selected_state.id, selected_state.conflicts.fetch(1).fetch(:symbol)]], calls
    end
  end

  def test_rejects_unknown_state_and_invalid_conflict_indexes
    automaton = build("class P\nexpect 1\nrule\nstart: start start | TOKEN\nend\n")
    counterexamples = Ibex::LALR::Counterexample.new(automaton)
    state = automaton.states.find { |candidate| !candidate.conflicts.empty? }

    error = assert_raises(ArgumentError) { counterexamples.for_conflict(999, 0) }
    assert_equal "unknown automaton state 999", error.message
    invalid = [nil, "0", -1, 999]
    invalid.each do |conflict_index|
      error = assert_raises(ArgumentError) { counterexamples.for_conflict(state.id, conflict_index) }
      expected = "conflict index #{conflict_index.inspect} is invalid for automaton state #{state.id}"
      assert_equal expected, error.message
    end
  end

  def test_all_retains_all_conflict_search_behavior
    automaton = build("class P\nexpect 1\nrule\nstart: start start | TOKEN\nend\n")
    calls = 0
    search = Object.new
    outcome = not_found_outcome
    search.define_singleton_method(:call) { outcome }
    factory = lambda do |*_arguments, **_options|
      calls += 1
      search
    end

    Ibex::LALR::ConflictSearch.stub(:new, factory) do
      examples = Ibex::LALR::Counterexample.new(automaton).all
      assert_equal automaton.states.sum { |state| state.conflicts.length }, calls
      assert_equal calls, examples.length
    end
  end

  private

  def not_found_outcome
    {
      status: :not_found, result: nil, explored: 0, exhausted: false,
      bounds: { max_tokens: 32, max_configurations: 50_000 }
    }
  end

  def build(source)
    ast = Ibex::Frontend::Parser.new(source, file: "counterexample-selection.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end
end
