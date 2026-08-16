# frozen_string_literal: true

require_relative "../test_helper"

class ImpactPropagationTest < Minitest::Test
  def test_recursive_components_stop_and_share_zero_distance
    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      start: expression
      expression: expression '+' term | term
      term: 'x'
      end
    GRAMMAR
    graph = Ibex::Impact::Graph.new(grammar)
    seed = grammar.symbol("expression").id
    nodes = Ibex::Impact::Propagation.new(graph).propagate([seed], :reference)

    assert_equal 0, nodes.fetch(seed).distance
    assert_equal 1, nodes.fetch(grammar.symbol("start").id).distance
    refute(nodes.values.any? { |node| node.distance > 2 })
  end

  def test_depth_limits_forward_reachability
    grammar = normalize("class P\nrule\nstart: pair\npair: value\nvalue: 'x'\nend\n")
    graph = Ibex::Impact::Graph.new(grammar)
    seed = grammar.symbol("value").id

    nodes = Ibex::Impact::Propagation.new(graph).propagate([seed], :first, max_depth: 1)

    assert_equal %w[pair value], nodes.keys.map { |id| grammar.symbol_by_id(id).name }.sort
  end

  def test_first_witness_uses_a_first_dependency_production
    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      start: a
      a: X b | b
      b: "b"
      X: "x"
      end
    GRAMMAR
    graph = Ibex::Impact::Graph.new(grammar)
    seed = grammar.symbol("b").id
    node = Ibex::Impact::Propagation.new(graph).propagate([seed], :first).fetch(grammar.symbol("a").id)

    production = grammar.productions.fetch(node.witness.fetch(0).production)
    lhs = grammar.symbol_by_id(production.lhs).name
    rhs = production.rhs.map { |id| grammar.symbol_by_id(id).name }

    assert_equal "a -> b", "#{lhs} -> #{rhs.join(' ')}"
  end

  def test_scc_witness_starts_at_the_seed
    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      start: d
      d: b
      a: b
      b: a
      end
    GRAMMAR
    graph = Ibex::Impact::Graph.new(grammar)
    seed = grammar.symbol("a").id
    node = Ibex::Impact::Propagation.new(graph).propagate([seed], :reference).fetch(grammar.symbol("d").id)

    assert_equal "a", grammar.symbol_by_id(node.witness.fetch(0).source).name
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
