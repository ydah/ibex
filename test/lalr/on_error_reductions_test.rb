# frozen_string_literal: true

require_relative "../test_helper"

class OnErrorReductionsTest < Minitest::Test
  def test_fills_only_error_cells_for_a_completed_declared_nonterminal
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token ITEM END BAD
      %on_error_reduce wrapper
      rule
      start: wrapper END
      wrapper: ITEM
      end
    GRAMMAR
    automaton = Ibex::LALR::Builder.new(grammar).build
    production = grammar.productions.find { |candidate| grammar.symbol_by_id(candidate.lhs).name == "wrapper" }
    state = automaton.states.find do |candidate|
      candidate.items.any? do |item|
        item.production == production.id && item.dot == production.rhs.length
      end
    end
    reduction = { type: :reduce, production: production.id }

    assert_equal reduction, resolved_action(state, grammar.symbol("BAD").id)
    assert_equal reduction, resolved_action(state, grammar.symbol("$eof").id)
    assert_equal reduction, resolved_action(state, grammar.symbol("END").id)
  end

  def test_later_declaration_has_higher_priority
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token BAD
      %on_error_reduce low
      %on_error_reduce high
      rule
      start: low | high
      low:
      high:
      end
    GRAMMAR
    automaton = Ibex::LALR::Builder.new(grammar).build
    high = grammar.productions.find { |production| grammar.symbol_by_id(production.lhs).name == "high" }

    assert_equal(
      { type: :reduce, production: high.id },
      resolved_action(automaton.states.fetch(0), grammar.symbol("BAD").id)
    )
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "recovery.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def resolved_action(state, token_id)
    state.actions[token_id] || state.default_action
  end
end
