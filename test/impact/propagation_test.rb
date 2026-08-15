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

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
