# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class FrontendParserTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/grammar/comprehensive.y", __dir__)

  def parse(source, mode: :default)
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

  def test_parses_nested_ebnf_groups_and_alternatives
    source = "class P\nrule\nvalues: (A (B | C)?)+\nend\n"
    item = parse(source, mode: :extended).rules.first.alternatives.first.items.first
    assert_instance_of Ibex::Frontend::AST::Plus, item
    outer_group = item.item
    assert_instance_of Ibex::Frontend::AST::Group, outer_group
    inner_optional = outer_group.alternatives.first.last
    assert_instance_of Ibex::Frontend::AST::Optional, inner_optional
    names = inner_optional.item.alternatives.map { |alternative| alternative.first.name }
    assert_equal %w[B C], names
  end

  def test_pragma_extended_enables_extensions_in_default_mode_without_entering_the_ast
    source = "class P\npragma extended\nrule\nvalues: ITEM:first ITEM*\nend\n"
    ast = parse(source)
    items = ast.rules.first.alternatives.first.items

    assert_equal [], ast.declarations
    assert_equal "first", items.first.named_reference
    assert_instance_of Ibex::Frontend::AST::Star, items.last
  end

  def test_parses_extended_symbol_display_and_type_declarations
    source = <<~GRAMMAR
      class P
      pragma extended
      display NUM "number"
      type NUM "Integer"
      type expression "AST::Expression"
      rule
      expression: NUM
      end
    GRAMMAR
    declarations = parse(source).declarations

    display, token_type, expression_type = declarations
    assert_instance_of Ibex::Frontend::AST::DisplayName, display
    assert_equal %w[NUM number], [display.name, display.value]
    assert_instance_of Ibex::Frontend::AST::SemanticType, token_type
    assert_equal %w[NUM Integer], [token_type.name, token_type.value]
    assert_equal ["expression", "AST::Expression"], [expression_type.name, expression_type.value]
  end

  def test_parses_compact_declarations_and_explicit_empty_in_extended_mode
    source = <<~GRAMMAR
      class P
      pragma extended
      token PLUS "+"
      %expect-rr 1
      preclow
      %precedence PLUS
      prechigh
      rule
      start: %empty
      end
    GRAMMAR
    ast = parse(source)
    tokens, expectation, precedence = ast.declarations

    assert_equal ["PLUS"], tokens.names
    assert_equal({ "PLUS" => "+" }, tokens.aliases)
    assert_equal 1, expectation.conflicts
    assert_instance_of Ibex::Frontend::AST::ExpectRR, expectation
    assert_equal :precedence, precedence.levels.first.associativity
    assert_instance_of Ibex::Frontend::AST::Empty, ast.rules.first.alternatives.first.items.first
  end

  def test_parses_typed_and_untyped_constructor_parameters
    source = <<~GRAMMAR
      class P
      pragma extended
      %param context "Hash[Symbol, Integer]"
      %param lexer
      rule
      start: TOKEN
      end
    GRAMMAR
    context, lexer = parse(source).declarations

    assert_equal ["context", "Hash[Symbol, Integer]"], [context.name, context.semantic_type]
    assert_nil lexer.semantic_type
    assert_instance_of Ibex::Frontend::AST::Parameter, context
    assert_instance_of Ibex::Frontend::AST::Parameter, lexer
  end

  def test_parses_symbol_value_printers
    source = <<~GRAMMAR
      class P
      pragma extended
      %printer NUM { "number=\#{value}" }
      %printer start { value.inspect }
      rule
      start: NUM
      end
    GRAMMAR
    token_printer, rule_printer = parse(source).declarations

    assert_equal ["NUM", " \"number=\#{value}\" "], [token_printer.name, token_printer.code]
    assert_equal ["start", " value.inspect "], [rule_printer.name, rule_printer.code]
    assert_instance_of Ibex::Frontend::AST::Printer, token_printer
  end

  def test_parses_multiple_start_symbols_in_extended_mode
    source = <<~GRAMMAR
      class P
      pragma extended
      start program expression
      rule
      program: PROGRAM
      expression: EXPRESSION
      end
    GRAMMAR
    declaration = parse(source).declarations.fetch(0)

    assert_instance_of Ibex::Frontend::AST::Start, declaration
    assert_equal %w[program expression], declaration.names
    assert_equal(
      { node: "Start", names: %w[program expression], loc: declaration.loc.to_h },
      declaration.to_h
    )
  end

  def test_rejects_new_declarations_without_extended_mode
    {
      "%expect-rr 0" => "expect-rr declarations require extended mode",
      "%param context" => "%param require extended mode",
      "%printer PLUS { value }" => "%printer require extended mode",
      "start program expression" => "multiple start symbols require extended mode",
      "prechigh\n%precedence PLUS\npreclow" => "%precedence require extended mode"
    }.each do |declaration, message|
      error = assert_raises(Ibex::Error) do
        parse("class P\n#{declaration}\nrule\nstart: PLUS\nend\n")
      end
      assert_includes error.message, message
    end

    error = assert_raises(Ibex::Error) { parse("class P\nrule\nstart: %empty\nend\n") }
    assert_includes error.message, "%empty require extended mode"
  end

  def test_rejects_symbol_metadata_in_default_mode_and_empty_values
    error = assert_raises(Ibex::Error) do
      parse("class P\ndisplay NUM \"number\"\nrule\ns: NUM\nend\n")
    end
    assert_equal "grammar.y:2:1: display declarations require extended mode", error.message

    error = assert_raises(Ibex::Error) do
      parse("class P\ntype NUM \"Integer\"\nrule\ns: NUM\nend\n")
    end
    assert_equal "grammar.y:2:1: type declarations require extended mode", error.message

    error = assert_raises(Ibex::Error) do
      parse("class P\npragma extended\ntype NUM \"\"\nrule\ns: NUM\nend\n")
    end
    assert_equal "grammar.y:3:10: type value must not be empty", error.message
  end

  def test_rejects_unknown_duplicate_and_misplaced_pragmas_with_locations
    error = assert_raises(Ibex::Error) { parse("class P\npragma future\nrule\ns: X\nend\n") }
    assert_equal "grammar.y:2:8: unknown pragma future", error.message

    error = assert_raises(Ibex::Error) do
      parse("class P\npragma extended\npragma extended\nrule\ns: X\nend\n")
    end
    assert_equal "grammar.y:3:1: duplicate pragma extended", error.message

    error = assert_raises(Ibex::Error) do
      parse("class P\ntoken X\npragma extended\nrule\ns: X\nend\n")
    end
    assert_match(/grammar\.y:3:1:/, error.message)
  end

  def test_rejects_extensions_in_default_mode
    error = assert_raises(Ibex::Error) { parse("class P\nrule\ns: ITEM*\nend\n") }
    assert_equal "grammar.y:3:8: EBNF suffixes require extended mode", error.message

    error = assert_raises(Ibex::Error) { parse("class P\nrule\ns: (ITEM)\nend\n") }
    assert_equal "grammar.y:3:4: EBNF groups require extended mode", error.message
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
