# frozen_string_literal: true

require_relative "../test_helper"

class DefaultReductionsTest < Minitest::Test
  ERROR_ACTION = { type: :error }.freeze

  def test_selects_the_lowest_production_deterministically_when_counts_tie
    state = automaton_state(
      0 => reduce(2), 1 => reduce(1), 2 => reduce(2),
      3 => reduce(1), 4 => reduce(2), 5 => reduce(1)
    )

    first = optimize(state, 0..5)
    second = optimize(state, 0..5)

    assert_equal reduce(1), first.default_action
    assert_equal first.to_h(grammar(0..5)), second.to_h(grammar(0..5))
    assert_same first, optimize(first, 0..5)
    assert_equal 4, encoded_size(first)
    assert_operator encoded_size(first), :<, encoded_size(state)
  end

  def test_materializes_error_masks_and_preserves_every_terminal_lookup
    state = automaton_state(0 => reduce(3), 2 => reduce(3), 3 => reduce(3), 4 => { type: :shift, state: 7 })

    optimized = optimize(state, 0..4)

    assert_equal reduce(3), optimized.default_action
    assert_equal ERROR_ACTION, optimized.actions.fetch(1)
    (0..4).each do |token_id|
      assert_equal action_at(state, token_id), action_at(optimized, token_id), "token #{token_id} changed"
    end
    assert_operator encoded_size(optimized), :<, encoded_size(state)
  end

  def test_leaves_a_state_unchanged_when_the_encoding_would_not_shrink
    state = automaton_state(0 => reduce(0), 2 => reduce(0))

    optimized = optimize(state, 0..3)

    assert_same state, optimized
    assert_nil optimized.default_action
  end

  private

  def optimize(state, terminal_ids)
    Ibex::LALR::DefaultReductions.optimize(state, terminal_ids: terminal_ids.to_a)
  end

  def automaton_state(actions)
    Ibex::IR::AutomatonState.new(id: 0, items: [], transitions: {}, actions: actions, gotos: {})
  end

  def reduce(production) = { type: :reduce, production: production }

  def encoded_size(state) = state.actions.length + (state.default_action ? 1 : 0)

  def action_at(state, token_id)
    state.actions[token_id] || state.default_action || ERROR_ACTION
  end

  def grammar(terminal_ids)
    symbols = terminal_ids.map do |id|
      Ibex::IR::GrammarSymbol.new(id: id, name: "T#{id}", kind: :terminal)
    end
    Ibex::IR::Grammar.new(class_name: "P", superclass: nil, start: "T0", expect: 0, options: {},
                          symbols: symbols, productions: [], user_code: {}, conversions: {}, warnings: [])
  end
end
