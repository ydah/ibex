# frozen_string_literal: true

require_relative "../test_helper"

class VisualizationTest < Minitest::Test
  def automaton
    source = <<~GRAMMAR
      class P
      rule
      start: start TOKEN | TOKEN
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "visual.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def test_dot_is_a_linked_graph
    dot = Ibex::Codegen::Dot.render(automaton)
    assert dot.start_with?("digraph ibex_automaton")
    assert_includes dot, "state_0 -> state_"
    assert_includes dot, "label=\"TOKEN\""
  end

  def test_html_is_self_contained_and_navigable
    html = Ibex::Codegen::HTML.render(automaton)
    assert_includes html, 'id="state-0"'
    assert_includes html, 'href="#rules"'
    assert_includes html, 'id="rule-0"'
    refute_match(%r{https?://}, html)
  end
end
