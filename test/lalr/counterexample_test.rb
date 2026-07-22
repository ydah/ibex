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
    assert example[:unifying]
    assert_equal %w[IF ID THEN IF ID THEN ID ELSE ID], example[:sentence]
    assert_equal "ELSE", example[:sentence][example[:lookahead_index]]
    kinds = example[:interpretations].map { |item| item[:kind] }
    assert_equal %i[shift reduce], kinds
    trees = example[:interpretations].map { |item| item[:tree] }
    tree_symbols = trees.map { |tree| tree[:symbol] }
    assert_equal %w[stmt stmt], tree_symbols
    refute_equal trees.first, trees.last
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
    assert example[:unifying]
    assert_equal ["TOKEN"], example[:sentence]
    assert_equal 2, example[:interpretations].length
    productions = example[:interpretations].map { |item| item[:production] }
    assert_equal [2, 3], productions
  end

  def test_falls_back_for_a_nonunifying_lalr_conflict
    automaton = build(<<~GRAMMAR)
      class P
      rule
      start: first 'a' 'd'
           | second 'b' 'd'
           | first 'b' 'e'
           | second 'a' 'e'
      first: 'c'
      second: 'c'
      end
    GRAMMAR
    examples = Ibex::LALR::Counterexample.new(automaton).all
    assert examples.any?
    refute examples.first[:unifying]
  end

  def test_report_includes_unifying_counterexample_and_derivations
    automaton = build("class P\nexpect 1\nrule\nstart: start start | TOKEN\nend\n")
    report = Ibex::Codegen::Report.render(automaton)
    assert_includes report, "unifying counterexample:"
    assert_includes report, "shift derivation:"
    assert_includes report, "reduce derivation:"
  end
end
