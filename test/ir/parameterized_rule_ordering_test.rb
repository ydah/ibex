# frozen_string_literal: true

require_relative "../test_helper"

class IRParameterizedRuleOrderingTest < Minitest::Test
  def test_lowers_an_earlier_ebnf_item_before_scheduling_a_later_parameter_call
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM
      rule
      child(X): X
      outer(X): X? child(X)
      start: outer(NUM)
      end
    GRAMMAR

    assert_equal %w[$parameter_1 $optional_2 $parameter_3], helper_names(grammar)
    assert_equal(
      [
        ["$optional_2", :optional_expansion, "outer"],
        ["$optional_2", :optional_expansion, "outer"],
        ["$parameter_3", :user, "child"],
        ["$parameter_1", :user, "outer"],
        ["start", :user, nil]
      ],
      production_order(grammar)
    )
  end

  def test_preserves_recursive_group_mid_action_and_separated_list_order
    grammar = normalize(<<~GRAMMAR)
      class P
      pragma extended
      token NUM COMMA
      rule
      left(X): X
      right(X): X
      outer(X): (left(X)) { result = nil } separated_list(X, right(COMMA))
      start: outer(NUM)
      end
    GRAMMAR

    assert_equal(
      %w[$parameter_1 $group_2 $parameter_3 $inline_4 $parameter_5 $separated_list_6],
      helper_names(grammar)
    )
    assert_equal(
      [
        ["$parameter_3", :user, "left"],
        ["$group_2", :group_expansion, "outer"],
        ["$inline_4", :inline_action, "outer"],
        ["$parameter_5", :user, "right"],
        ["$separated_list_6", :separated_list_expansion, "outer"],
        ["$separated_list_6", :separated_list_expansion, "outer"],
        ["$separated_list_6", :separated_list_expansion, "outer"],
        ["$parameter_1", :user, "outer"],
        ["start", :user, nil]
      ],
      production_order(grammar)
    )
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "parameter.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end

  def helper_names(grammar)
    grammar.nonterminals.filter_map do |symbol|
      symbol.name if symbol.name.start_with?("$")
    end
  end

  def production_order(grammar)
    grammar.productions.map do |production|
      [
        grammar.symbol_by_id(production.lhs).name,
        production.origin.fetch(:kind),
        production.expansion&.dig(:parameter, :rule)
      ]
    end
  end
end
