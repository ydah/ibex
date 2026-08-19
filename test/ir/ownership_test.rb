# frozen_string_literal: true

require_relative "../test_helper"

class IROwnershipTest < Minitest::Test
  def test_production_owns_a_frozen_copy_of_caller_values
    rhs = [1, 2]
    origin = { kind: :rule, metadata: { name: "start" } }
    production = Ibex::IR::Production.new(
      id: 0, lhs: 3, rhs: rhs, action: nil, precedence_override: nil, origin: origin
    )

    rhs << 4
    origin.fetch(:metadata)[:name] = "changed"

    assert_equal [1, 2], production.rhs
    assert_equal "start", production.origin.dig(:metadata, :name)
    assert_predicate production.rhs, :frozen?
    refute_predicate rhs, :frozen?
    refute_predicate origin, :frozen?
  end

  def test_grammar_does_not_freeze_caller_collections
    symbol = Ibex::IR::GrammarSymbol.new(id: 0, name: "start", kind: :nonterminal)
    symbols = [symbol]
    productions = []
    options = {}
    grammar = Ibex::IR::Grammar.new(
      class_name: "Ownership", superclass: nil, start: "start", expect: 0,
      options: options, symbols: symbols, productions: productions,
      user_code: {}, conversions: {}, warnings: []
    )

    symbols.clear
    productions << :caller_only
    options[:changed] = true

    assert_equal [symbol], grammar.symbols
    assert_empty grammar.productions
    assert_empty grammar.options
    assert_predicate grammar.symbols, :frozen?
    assert_predicate grammar.options, :frozen?
    refute_predicate symbols, :frozen?
    refute_predicate productions, :frozen?
    refute_predicate options, :frozen?
  end
end
