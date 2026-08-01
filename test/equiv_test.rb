# frozen_string_literal: true

require_relative "test_helper"

class EquivTest < Minitest::Test
  EQUIVALENT_CASES = [
    ["rule wrapper", "start: A", "start: wrapped\nwrapped: A"],
    ["alternative order", "start: A | B", "start: B | A"],
    ["recursion direction", "start: list\nlist: A | list COMMA A", "start: list\nlist: A | A COMMA list"],
    ["common prefix", "start: A B | A C", "start: A tail\ntail: B | C"],
    ["common suffix", "start: A C | B C", "start: head C\nhead: A | B"],
    ["optional wrapper", "start: %empty | A", "start: maybe\nmaybe: %empty | A"],
    ["sequence wrapper", "start: A B C", "start: A pair\npair: B C"],
    ["distributed choice", "start: A tail | B tail\ntail: C | D", "start: A C | A D | B C | B D"],
    ["alternative wrappers", "start: alpha | beta\nalpha: A\nbeta: B", "start: A | B"],
    ["epsilon concatenation", "start: A empty B\nempty: %empty", "start: A B"]
  ].freeze #: Array[[String, String, String]]

  NON_EQUIVALENT_CASES = [
    ["different terminal", "start: A", "start: B"],
    ["empty versus token", "start: %empty", "start: A"],
    ["missing suffix", "start: A B", "start: A"],
    ["missing alternative", "start: A | B", "start: A"],
    ["reversed sequence", "start: A B", "start: B A"],
    ["one versus repeated", "start: A", "start: list\nlist: A | list A"],
    ["optional versus empty", "start: %empty | A", "start: %empty"],
    ["missing factored branch", "start: A B | A C", "start: A B"],
    ["plus versus star", "start: plus\nplus: A | plus A", "start: star\nstar: %empty | star A"],
    ["different third token", "start: A B C", "start: A B D"]
  ].freeze #: Array[[String, String, String]]

  def test_ten_known_equivalent_pairs_report_no_difference
    assert_equal 10, EQUIVALENT_CASES.length
    assert_equal 10, EQUIVALENT_CASES.map { |_label, left, right| [left, right] }.uniq.length

    EQUIVALENT_CASES.each_with_index do |(label, left_rules, right_rules), index|
      left = automaton("EquivalentLeft#{index}", left_rules, extended: extended?(left_rules))
      right = automaton("EquivalentRight#{index}", right_rules, extended: extended?(right_rules))

      report = Ibex::Equiv.new(left, right, sample_count: 20, max_tokens: 6).run

      assert_equal "no_difference_within_bounds", report.fetch(:result), label
    end
  end

  def test_ten_known_non_equivalent_pairs_return_concrete_witnesses
    assert_equal 10, NON_EQUIVALENT_CASES.length
    assert_equal 10, NON_EQUIVALENT_CASES.map { |_label, left, right| [left, right] }.uniq.length

    NON_EQUIVALENT_CASES.each_with_index do |(label, left_rules, right_rules), index|
      left = automaton("DifferentLeft#{index}", left_rules, extended: extended?(left_rules))
      right = automaton("DifferentRight#{index}", right_rules, extended: extended?(right_rules))

      error = assert_raises(Ibex::Equiv::Difference, label) do
        Ibex::Equiv.new(left, right, sample_count: 20, max_tokens: 6).run
      end

      assert_kind_of Array, error.details.fetch(:witness), label
      refute_equal error.details.dig(:outcomes, :left), error.details.dig(:outcomes, :right), label
    end
  end

  def test_bounded_product_search_handles_nonidentical_equivalent_grammars
    left = automaton("Direct", "start: TOKEN")
    right = automaton("Indirect", "start: wrapper\nwrapper: TOKEN")

    report = Ibex::Equiv.new(
      left, right, sample_count: 4, max_tokens: 3, max_configurations: 100
    ).run

    assert_equal "no_difference_within_bounds", report.fetch(:result)
    assert_equal false, report.fetch(:structural_identity)
    assert_operator report.dig(:checked, :product_configurations), :>, 0
    assert_equal Ibex::Equiv::CAVEAT, report.fetch(:statement)
  end

  def test_product_budget_exhaustion_is_distinct
    left = automaton("DirectBudget", "start: TOKEN")
    right = automaton("IndirectBudget", "start: wrapper\nwrapper: TOKEN")

    error = assert_raises(Ibex::Equiv::BudgetExceeded) do
      Ibex::Equiv.new(
        left, right, sample_count: 1, max_tokens: 3, max_configurations: 1
      ).run
    end

    assert_equal "product_bfs", error.details.fetch(:phase)
  end

  def test_empty_sentence_is_the_shortest_witness
    left = automaton("AcceptEmpty", "start: %empty", extended: true)
    right = automaton("RejectEmpty", "start: TOKEN", extended: true)

    error = assert_raises(Ibex::Equiv::Difference) do
      Ibex::Equiv.new(left, right, sample_count: 1, max_tokens: 2).run
    end

    assert_empty error.details.fetch(:witness)
  end

  def test_rule_mapping_can_establish_structural_identity
    left = automaton("OldRule", "start: old\nold: TOKEN")
    right = automaton("NewRule", "start: new\nnew: TOKEN")

    report = Ibex::Equiv.new(left, right, rule_map: { "old" => "new" }).run

    assert_equal true, report.fetch(:structural_identity)
    assert_equal({ "old" => "new" }, report.fetch(:rule_map))
    assert_equal "no_difference_within_bounds", report.dig(:tree, :result)
  end

  def test_rule_mapping_detects_a_bounded_tree_difference
    left = automaton("OldTree", "start: old\nold: TOKEN @node OldValue(value)", extended: true)
    right = automaton("NewTree", "start: new\nnew: TOKEN @node NewValue(value)", extended: true)

    error = assert_raises(Ibex::Equiv::Difference) do
      Ibex::Equiv.new(left, right, sample_count: 1, rule_map: { "old" => "new" }).run
    end

    assert_equal "tree", error.details.fetch(:difference_kind)
    assert_equal ["TOKEN"], error.details.fetch(:witness)
  end

  def test_semantic_actions_are_opaque
    left = automaton("SafeLeft", 'start: TOKEN { raise "must not run" }')
    right = automaton("SafeRight", "start: TOKEN { exit! }")

    assert_equal "no_difference_within_bounds", Ibex::Equiv.new(left, right).run.fetch(:result)
  end

  private

  def extended?(rules)
    rules.include?("%empty")
  end

  def automaton(class_name, rules, extended: false)
    pragma = "pragma extended\n" if extended
    source = "class #{class_name}\n#{pragma}rule\n#{rules}\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "#{class_name}.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    Ibex::LALR::Builder.new(grammar).build
  end
end
