# frozen_string_literal: true

require_relative "../test_helper"

class CounterexampleTest < Minitest::Test
  def build(source)
    ast = Ibex::Frontend::Parser.new(source, file: "counterexample.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def test_shift_reduce_witness_reaches_conflict_with_both_interpretations
    automaton = build(<<~GRAMMAR)
      class P
      token IF THEN ELSE ID
      expect 1
      rule
      stmt: IF expr THEN stmt
          | IF expr THEN stmt ELSE stmt
          | ID
      expr: ID
      end
    GRAMMAR
    example = Ibex::LALR::Counterexample.new(automaton).all.first
    assert_equal :shift_reduce, example[:type]
    assert_equal "ELSE", example[:sentence].last
    kinds = example[:interpretations].map { |item| item[:kind] }
    assert_equal %i[shift reduce], kinds
    assert example[:interpretations].last[:tree][:children].any?
  end

  def test_reduce_reduce_witness_has_two_derivation_trees
    automaton = build(<<~GRAMMAR)
      class P
      rule
      start: first | second
      first: TOKEN
      second: TOKEN
      end
    GRAMMAR
    example = Ibex::LALR::Counterexample.new(automaton).all.first
    assert_equal :reduce_reduce, example[:type]
    assert_equal 2, example[:interpretations].length
    symbols = example[:interpretations].map { |item| item[:tree][:symbol] }
    assert_equal %w[first second], symbols
  end

  def test_report_includes_shortest_witness
    automaton = build("class P\nexpect 1\nrule\nstart: start start | TOKEN\nend\n")
    report = Ibex::Codegen::Report.render(automaton)
    assert_includes report, "witness:"
  end
end
