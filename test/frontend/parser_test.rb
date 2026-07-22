# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class FrontendParserTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/grammar/comprehensive.y", __dir__)

  def parse(source, mode: :racc)
    Ibex::Frontend::Parser.new(source, file: "grammar.y", mode: mode).parse
  end

  def test_comprehensive_fixture_matches_golden_ast
    ast = Ibex::Frontend::Parser.new(File.read(FIXTURE), file: "comprehensive.y").parse
    golden = JSON.parse(File.read(File.expand_path("../fixtures/ast/comprehensive.json", __dir__)))
    assert_equal golden, JSON.parse(JSON.pretty_generate(ast.to_h))
  end

  def test_parses_both_precedence_directions
    source = "class P\npreclow\nleft LOW\nright HIGH\nprechigh\nrule\ns: LOW\nend\n"
    precedence = parse(source).declarations.first
    assert_equal :low_to_high, precedence.direction
    assert_equal %i[left right], precedence.levels.map(&:associativity)
  end

  def test_parses_extended_suffixes_named_references_and_lists
    source = <<~GRAMMAR
      class P
      rule
      values : ITEM:first ITEM? ITEM* ITEM+ separated_list(ITEM, ',')
      end
    GRAMMAR
    items = parse(source, mode: :extended).rules.first.alternatives.first.items
    assert_equal "first", items[0].named_reference
    assert_instance_of Ibex::Frontend::AST::Optional, items[1]
    assert_instance_of Ibex::Frontend::AST::Star, items[2]
    assert_instance_of Ibex::Frontend::AST::Plus, items[3]
    assert_instance_of Ibex::Frontend::AST::SeparatedList, items[4]
  end

  def test_rejects_extensions_in_racc_mode
    error = assert_raises(Ibex::Error) { parse("class P\nrule\ns: ITEM*\nend\n") }
    assert_equal "grammar.y:3:8: EBNF suffixes require extended mode", error.message
  end

  def test_reports_missing_rule_and_end_with_locations
    error = assert_raises(Ibex::Error) { parse("class P\ntoken X\n") }
    assert_match(/grammar\.y:3:1: expected rule/, error.message)

    error = assert_raises(Ibex::Error) { parse("class P\nrule\ns: X\n") }
    assert_match(/grammar\.y:4:1: expected end/, error.message)
  end

  def test_rejects_invalid_precedence_line
    source = "class P\nprechigh\nmiddle X\npreclow\nrule\ns: X\nend\n"
    error = assert_raises(Ibex::Error) { parse(source) }
    assert_match(/grammar\.y:3:1: expected left or right or nonassoc/, error.message)
  end
end
