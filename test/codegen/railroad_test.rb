# frozen_string_literal: true

require_relative "../test_helper"

class RailroadTest < Minitest::Test
  def test_renders_deterministic_self_contained_svg_from_lowered_grammar
    grammar = diagram_grammar

    first = Ibex::Codegen::Railroad.render(grammar)
    resumed = Ibex::Codegen::Railroad.render(Ibex::IR::Serialize.load(Ibex::IR::Serialize.dump(grammar)))

    assert_equal first, resumed
    assert first.start_with?(%(<?xml version="1.0" encoding="UTF-8"?>\n<svg))
    assert_includes first, %(xmlns="http://www.w3.org/2000/svg")
    assert_includes first, "<style>"
    assert_includes first, "<line "
    assert_includes first, "<rect "
    assert_includes first, %(data-production="0")
    assert_includes first, %(id="nonterminal-6")
    assert_includes first, "ITEM*"
    assert_includes first, "ε"
    refute_includes first, "<script"
    refute_match(/<(?:script|link)\b|(?:src|href)="https?:/i, first)
  end

  def test_escapes_symbol_display_names_as_xml_text
    svg = Ibex::Codegen::Railroad.render(diagram_grammar)

    assert_includes svg, "&lt;script&gt;&amp;"
    refute_includes svg, "<script>&"
  end

  def test_replaces_xml_forbidden_control_characters_from_resumed_ir
    data = JSON.parse(Ibex::IR::Serialize.dump(diagram_grammar))
    data["class_name"] = "Diagram\u0000Injected"
    grammar = Ibex::IR::Serialize.load(JSON.generate(data))

    svg = Ibex::Codegen::Railroad.render(grammar)

    refute_includes svg, "\u0000"
    assert_includes svg, "Diagram\uFFFDInjected"
  end

  def test_renders_escaped_wrapped_rule_documentation_without_overlapping_productions
    description = "<unsafe>& #{'documented ' * 12}"
    source = <<~GRAMMAR
      class Diagram
      rule
      ## #{description}
      ## second line
      start: TOKEN
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "diagram.y", mode: :extended).parse
    svg = Ibex::Codegen::Railroad.render(Ibex::Normalizer.new(ast, mode: :extended).normalize)

    assert_includes svg, "<desc>&lt;unsafe&gt;&amp;"
    assert_includes svg, "class=\"rule-documentation\""
    assert_operator svg.scan("class=\"rule-documentation\"").length, :>=, 3
    refute_includes svg, "<unsafe>"
    documentation_y = svg[/class="rule-documentation" x="\d+" y="(\d+)"/, 1].to_i
    production_y = svg[/class="production"[^>]+translate\(0 (\d+)\)/, 1].to_i
    assert_operator production_y, :>, documentation_y
  end

  private

  def diagram_grammar
    source = <<~GRAMMAR
      class Diagram
      pragma extended
      token ITEM BAD
      display BAD "<script>&"
      rule
      start: ITEM* BAD empty
      empty:
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "diagram.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end
end
