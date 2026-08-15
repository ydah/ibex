# frozen_string_literal: true

require_relative "../test_helper"

class ImpactGraphTest < Minitest::Test
  def test_follow_first_edge_tracks_first_to_follow_propagation
    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      start: left right
      left: 'a'
      right: 'b'
      end
    GRAMMAR
    graph = Ibex::Impact::Graph.new(grammar)
    edge = graph.edges(:follow_first).find do |candidate|
      grammar.symbol_by_id(candidate.source).name == "right" &&
        grammar.symbol_by_id(candidate.target).name == "left"
    end

    refute_nil edge
    assert_equal :follow_first, edge.kind
    assert_equal 0, edge.production
  end

  def test_edge_order_is_deterministic
    grammar = normalize("class P\nrule\nstart: left right\nleft: 'a'\nright: 'b'\nend\n")
    graph = Ibex::Impact::Graph.new(grammar)

    first = graph.edges(:all).map(&:sort_key)
    second = Ibex::Impact::Graph.new(grammar).edges(:all).map(&:sort_key)
    assert_equal first, second
    assert_equal first.sort, first
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
