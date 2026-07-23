# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"

class FrontendSymbolMetadataTest < Minitest::Test
  def test_generated_parser_matches_bootstrap
    source = <<~GRAMMAR
      class P
      pragma extended
      display NUM "number"
      type NUM "Integer"
      type start "AST::Node"
      rule
      start: NUM
      end
    GRAMMAR

    assert_equal bootstrap(source).to_h, generated(source).to_h
  end

  def test_generated_parser_matches_bootstrap_errors
    grammars = [
      "class P\ndisplay NUM \"number\"\nrule\nstart: NUM\nend\n",
      "class P\ntype NUM \"Integer\"\nrule\nstart: NUM\nend\n",
      "class P\npragma extended\ndisplay NUM \"\"\nrule\nstart: NUM\nend\n",
      "class P\npragma extended\ntype NUM \"\"\nrule\nstart: NUM\nend\n",
      "class P\npragma extended\ntype NUM \"Array[\\tString]\"\nrule\nstart: NUM\nend\n",
      "class P\npragma extended\ntype NUM\n\"Integer\"\nrule\nstart: NUM\nend\n"
    ]

    grammars.each do |grammar|
      bootstrap_error = assert_raises(Ibex::Error) { bootstrap(grammar) }
      generated_error = assert_raises(Ibex::Error) { generated(grammar) }
      assert_equal bootstrap_error.message, generated_error.message
    end
  end

  def test_racc_token_declaration_keeps_display_and_type_as_symbols
    source = <<~GRAMMAR
      class P
      token type display
      rule
      start: type display
      end
    GRAMMAR

    bootstrap_root = bootstrap(source)
    generated_root = generated(source)

    assert_equal bootstrap_root.to_h, generated_root.to_h
    assert_equal %w[type display], bootstrap_root.declarations.fetch(0).names
  end

  def test_missing_type_value_has_the_same_positioned_error
    source = "class P\npragma extended\ntype NUM\n"

    bootstrap_error = assert_raises(Ibex::Error) { bootstrap(source) }
    generated_error = assert_raises(Ibex::Error) { generated(source) }

    assert_equal "grammar.y:4:1: expected a quoted string, got eof", bootstrap_error.message
    assert_equal bootstrap_error.message, generated_error.message
  end

  private

  def bootstrap(source)
    Ibex::Frontend::BootstrapParser.new(source, file: "grammar.y").parse
  end

  def generated(source)
    Ibex::Frontend::Parser.new(source, file: "grammar.y").parse
  end
end
