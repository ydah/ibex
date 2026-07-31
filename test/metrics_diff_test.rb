# frozen_string_literal: true

require_relative "test_helper"

class MetricsDiffTest < Minitest::Test
  def test_metrics_report_deterministic_grammar_and_automaton_counts
    automaton = build(<<~GRAMMAR)
      class Recursive
      pragma extended
      rule
      start: a
      a: b
       | TOKEN
       | %empty
      b: a
      end
    GRAMMAR

    report = Ibex::Metrics.new(automaton).to_h

    assert_equal "metrics", report.fetch(:ibex_report)
    assert_equal 5, report.dig(:grammar, :alternatives)
    assert_equal 1, report.dig(:grammar, :epsilon_productions)
    assert_equal %w[a b], report.dig(:grammar, :recursive_nonterminals)
    assert_equal 2, report.dig(:grammar, :recursion_component_depth)
    assert_operator report.dig(:automaton, :states), :>, 0
  end

  def test_diff_classifies_added_removed_and_changed_rules
    before = build(<<~GRAMMAR)
      class Before
      rule
      start: alpha
      alpha: A
      legacy: OLD
      end
    GRAMMAR
    after = build(<<~GRAMMAR)
      class After
      rule
      start: alpha
           | beta
      alpha: B
      beta: NEW
      end
    GRAMMAR

    report = Ibex::Diff.new(before, after).to_h
    rules = report.fetch(:rules)

    assert_includes rules.fetch(:added).map { |item| item.fetch(:id) }, "beta"
    assert_includes rules.fetch(:removed).map { |item| item.fetch(:id) }, "legacy"
    assert_includes rules.fetch(:changed).map { |item| item.fetch(:id) }, "alpha"
    assert_equal 1, report.dig(:metrics, :productions, :delta)
  end

  def test_diff_is_deterministic
    before = build("class P\nrule\nstart: A\nend\n")
    after = build("class P\nrule\nstart: A | B\nend\n")

    assert_equal Ibex::Diff.new(before, after).to_h, Ibex::Diff.new(before, after).to_h
  end

  private

  def build(source)
    ast = Ibex::Frontend::Parser.new(source, file: "analysis.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    Ibex::LALR::Builder.new(grammar).build
  end
end
