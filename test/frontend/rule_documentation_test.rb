# frozen_string_literal: true

require_relative "../test_helper"

class FrontendRuleDocumentationTest < Minitest::Test
  def test_attaches_indented_multiline_crlf_comments_and_strips_one_space
    source = "class P\r\nrule\r\n  ## First line\r\n\t##  indented detail\r\n  value: TOKEN\r\nend\r\n"
    rule = parse(source).rules.fetch(0)

    assert_equal "First line\n indented detail", rule.documentation
    assert_equal 5, rule.loc.line
  end

  def test_blank_single_hash_and_nontrivia_lines_break_documentation_blocks
    source = <<~GRAMMAR
      class P
      rule
      ## hidden by blank

      blank: TOKEN
      ## hidden by ordinary comment
      # ordinary
      ordinary: TOKEN
      ## belongs only to previous definition
      previous: TOKEN
      following: TOKEN
      end
    GRAMMAR

    blank, ordinary, previous, following = parse(source).rules
    assert_nil blank.documentation
    assert_nil ordinary.documentation
    assert_equal "belongs only to previous definition", previous.documentation
    assert_nil following.documentation
  end

  def test_hashes_inside_an_opaque_action_do_not_attach_to_the_next_rule
    source = <<~GRAMMAR
      class P
      rule
      first: TOKEN {
        text = <<~DOC
      ## not a rule comment
      DOC
        result = text
      }
      second: TOKEN
      end
    GRAMMAR

    first, second = parse(source).rules
    assert_nil first.documentation
    assert_nil second.documentation
  end

  def test_fragment_rules_are_enriched_without_mutating_the_generated_ast
    source = "fragment\nrule\n## Fragment helper\nhelper: TOKEN\nend\n"
    document = Ibex::Frontend::Lexer.new(source, file: "fragment.y").tokenize_document
    raw = Ibex::Frontend::GeneratedParser.new(document.tokens, mode: :extended).parse
    enriched = Ibex::Frontend::RuleDocumentation.enrich(raw, document)

    assert_instance_of Ibex::Frontend::AST::Fragment, enriched
    assert_nil raw.rules.fetch(0).documentation
    assert_equal "Fragment helper", enriched.rules.fetch(0).documentation
    refute_same raw, enriched
    refute_same raw.rules.fetch(0), enriched.rules.fetch(0)

    parsed = Ibex::Frontend::Parser.new(source, file: "fragment.y", mode: :extended).parse_fragment
    assert_equal "Fragment helper", parsed.rules.fetch(0).documentation
  end

  private

  def parse(source)
    Ibex::Frontend::Parser.new(source, file: "rules.y", mode: :extended).parse
  end
end
