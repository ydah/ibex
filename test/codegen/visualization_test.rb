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

  def conflicted_automaton
    source = "class P\nexpect 1\nrule\nstart: start start | TOKEN\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "conflict.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end

  def test_dot_is_a_linked_graph
    dot = Ibex::Codegen::Dot.render(automaton)
    assert dot.start_with?("digraph ibex_automaton")
    assert_includes dot, "state_0 -> state_"
    assert_includes dot, "label=\"TOKEN\""
  end

  def test_mermaid_is_a_linked_graph
    mermaid = Ibex::Codegen::Mermaid.render(automaton)
    assert mermaid.start_with?("flowchart LR\n")
    assert_includes mermaid, "state_0"
    assert_match(/state_0 -->\|TOKEN\| state_\d+/, mermaid)
  end

  def test_html_is_self_contained_and_navigable
    html = Ibex::Codegen::HTML.render(automaton)
    assert_includes html, 'id="state-0"'
    assert_includes html, 'href="#rules"'
    assert_includes html, 'id="rule-0"'
    assert_includes html, 'id="state-search"'
    assert_includes html, 'id="conflict-only"'
    assert_includes html, 'id="conflict-neighborhood"'
    assert_includes html, "data-neighbors="
    refute_match(%r{https?://}, html)
  end

  def test_html_and_mermaid_highlight_conflicting_states
    conflicted = conflicted_automaton
    conflict_state = conflicted.states.find { |state| !state.conflicts.empty? }

    html = Ibex::Codegen::HTML.render(conflicted)
    assert_includes html, "state conflict-state"
    assert_includes html, "<option value=\"#{conflict_state.id}\">State #{conflict_state.id}</option>"

    mermaid = Ibex::Codegen::Mermaid.render(conflicted)
    assert_includes mermaid, "class state_#{conflict_state.id} conflict;"
    assert_includes mermaid, "classDef conflict"
  end

  def test_html_conflict_neighborhood_contains_exactly_one_hop
    conflicted = conflicted_automaton
    conflict_state = conflicted.states.find { |state| !state.conflicts.empty? }
    html = Ibex::Codegen::HTML.render(conflicted)
    neighbor_ids = html.match(/id="state-#{conflict_state.id}"[^>]+data-neighbors="([^"]+)"/)[1].split.map(&:to_i)
    incoming = conflicted.states.filter_map do |state|
      state.id if state.transitions.value?(conflict_state.id)
    end
    expected_neighbors = ([conflict_state.id] + conflict_state.transitions.values + incoming).uniq.sort
    assert_equal expected_neighbors, neighbor_ids
  end

  def test_reports_render_extended_ebnf_instead_of_internal_helper_names
    source = <<~GRAMMAR
      class Extended
      rule
      start: (A B)? C+ separated_list(D, ',')
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "extended.y", mode: :extended).parse
    extended = Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast, mode: :extended).normalize).build

    outputs = [
      Ibex::Codegen::Report.render(extended),
      Ibex::Codegen::Dot.render(extended),
      Ibex::Codegen::Mermaid.render(extended),
      Ibex::Codegen::HTML.render(extended)
    ]
    outputs.each do |output|
      assert_includes output, "(A B)?"
      assert_includes output, "C+"
      assert_includes output, "separated_list(D, ',')"
      refute_match(/\$(?:optional|plus|separated_list)_\d+/, output)
    end
  end

  def test_reports_fall_back_to_internal_names_for_older_schema_v1_origins
    source = "class Extended\nrule\nstart: A?\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "extended.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    data = JSON.parse(Ibex::IR::Serialize.dump(grammar))
    data.fetch("productions").each { |production| production.fetch("origin").delete("expression") }
    legacy_grammar = Ibex::IR::Serialize.load(JSON.generate(data))
    legacy_automaton = Ibex::LALR::Builder.new(legacy_grammar).build

    assert_match(/\$optional_\d+/, Ibex::Codegen::Report.render(legacy_automaton))
  end

  def test_reports_prefer_symbol_display_names
    source = <<~GRAMMAR
      class Displayed
      pragma extended
      display TOKEN "value"
      display start "document"
      rule
      start: TOKEN
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "displayed.y").parse
    displayed = Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build

    report = Ibex::Codegen::Report.render(displayed)
    assert_includes report, "$accept -> • document"
    refute_includes report, "$accept -> • start"

    [report, Ibex::Codegen::Dot.render(displayed),
     Ibex::Codegen::HTML.render(displayed)].each do |output|
      assert_includes output, "value"
      refute_includes output, "TOKEN"
    end
  end
end
