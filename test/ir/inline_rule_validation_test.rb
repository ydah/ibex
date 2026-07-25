# frozen_string_literal: true

require_relative "../test_helper"

class IRInlineRuleValidationTest < Minitest::Test
  def test_rejects_mixed_markings
    assert_normalization_error("inline.y:5:1: rule helper has both inline and ordinary definitions", <<~GRAMMAR)
      class P
      pragma extended
      rule
      %inline helper: A
      helper: B
      start: helper
      end
    GRAMMAR
  end

  def test_rejects_terminal_collisions_and_inline_start
    assert_normalization_error("inline.y:5:9: inline rule helper collides with terminal helper", <<~GRAMMAR)
      class P
      pragma extended
      token helper
      rule
      %inline helper: A
      start: helper
      end
    GRAMMAR
    assert_normalization_error("inline.y:3:1: inline rule helper cannot be the start symbol", <<~GRAMMAR)
      class P
      pragma extended
      start helper
      rule
      %inline helper: A
      end
    GRAMMAR
  end

  def test_rejects_cycles_through_ordinary_and_parameterized_rules
    assert_normalization_error(
      "inline.y:5:11: inline expansion cycle: helper -> ordinary -> helper", <<~GRAMMAR
        class P
        pragma extended
        rule
        %inline helper: ordinary
        ordinary: helper
        start: ordinary
        end
      GRAMMAR
    )
    assert_normalization_error("inline.y:4:20: inline expansion cycle: helper -> helper", <<~GRAMMAR)
      class P
      pragma extended
      rule
      %inline helper(X): helper(X)
      start: helper(A)
      end
    GRAMMAR
  end

  def test_unused_parameter_actuals_do_not_create_cycle_edges
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token TOKEN
      rule
      ignore(X): TOKEN
      forward(X): ignore(X)
      %inline helper: ordinary
      ordinary: forward(helper)
      start: ordinary
      end
    GRAMMAR

    assert_equal "ordinary", grammar.start
    assert_nil grammar.symbol("helper")
  end

  def test_transitively_live_parameter_actuals_still_create_cycle_edges
    assert_normalization_error(
      "inline.y:8:19: inline expansion cycle: helper -> ordinary -> helper",
      <<~GRAMMAR
        class P
        pragma extended
        token TOKEN
        rule
        consume(X): X
        forward(X): consume(X)
        %inline helper: ordinary
        ordinary: forward(helper)
        start: ordinary
        end
      GRAMMAR
    )
  end

  def test_ten_thousand_rule_acyclic_chain_uses_heap_worklists
    count = 10_000
    chain = count.times.map do |index|
      target = index == count - 1 ? "TOKEN" : "inline_#{index + 1}"
      "%inline inline_#{index}: #{target}"
    end
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token TOKEN
      rule
      #{chain.join("\n")}
      start: inline_0
      end
    GRAMMAR

    production = grammar.productions.find { |candidate| grammar.symbol_by_id(candidate.lhs).name == "start" }
    assert_equal [grammar.symbol("TOKEN").id], production.rhs
    assert_equal count + 1, production.action.composition.dig(:plan, :steps).length
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "inline.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end

  def assert_normalization_error(message, source)
    error = assert_raises(Ibex::Error) { normalize(source) }
    assert_equal message, error.message
  end
end
