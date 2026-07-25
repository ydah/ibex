# frozen_string_literal: true

require_relative "../test_helper"

class CodegenDocumentationTest < Minitest::Test
  def test_markdown_is_deterministic_and_escapes_documentation_and_symbols
    grammar = documented_grammar
    markdown = Ibex::Codegen::Documentation.render(grammar, format: :markdown)
    resumed = Ibex::IR::Serialize.load(Ibex::IR::Serialize.dump(grammar))

    assert_equal markdown, Ibex::Codegen::Documentation.render(resumed, format: "markdown")
    assert_includes markdown, "# Documentation grammar"
    assert_includes markdown, "## `value`"
    assert_includes markdown, "> &lt;script&gt;&amp; \\*em\\* \\[link\\]"
    assert_includes markdown, "> Second line\\."
    assert_includes markdown, "`&lt;token&amp;&gt;`"
    refute_includes markdown, "<script>"
  end

  def test_html_is_self_contained_accessible_and_escapes_all_text
    html = Ibex::Codegen::Documentation.render(documented_grammar, format: :html)

    assert html.start_with?("<!doctype html>\n<html lang=\"en\">")
    assert_includes html, "<main>"
    assert_includes html, "aria-labelledby=\"rule-"
    assert_includes html, "aria-label=\"Alternatives for value\""
    assert_includes html, "&lt;script&gt;&amp; *em* [link]"
    assert_includes html, "&lt;token&amp;&gt;"
    assert_includes html, "<br>"
    refute_includes html, "<script>"
    refute_match(/<(?:script|link)\b|(?:src|href)="https?:/i, html)
  end

  def test_markdown_code_spans_outgrow_backtick_runs_and_preserve_boundary_spaces
    markdown = Ibex::Codegen::Documentation.render(backtick_grammar, format: :markdown)

    assert_includes markdown, "``` `edge`` ```"
    assert_includes markdown, "````mid```run````"
    assert_includes markdown, "`  spaced  `"
  end

  def test_railroad_format_uses_the_documented_svg_renderer
    grammar = documented_grammar

    assert_equal Ibex::Codegen::Railroad.render(grammar),
                 Ibex::Codegen::Documentation.render(grammar, format: :railroad)
  end

  private

  def documented_grammar
    source = <<~GRAMMAR
      class Documentation
      pragma extended
      token TOKEN
      display TOKEN "<token&>"
      rule
      ## <script>& *em* [link]
      ## Second line.
      value: TOKEN |
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "documentation.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end

  def backtick_grammar
    source = <<~GRAMMAR
      class Backticks
      pragma extended
      token EDGE INTERNAL SPACED
      display EDGE "`edge``"
      display INTERNAL "mid```run"
      display SPACED " spaced "
      rule
      value: EDGE INTERNAL SPACED
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "backticks.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end
end
