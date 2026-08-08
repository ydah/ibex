# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"

class FrontendParserConfigurationTest < Minitest::Test
  ALGORITHMS = %w[slr lalr ielr lr1].freeze

  def test_generated_and_bootstrap_parsers_accept_the_closed_configuration_vocabulary
    ALGORITHMS.each do |algorithm|
      source = grammar("algorithm #{algorithm}\n  entries shared")
      generated = parse(source)
      bootstrap = Ibex::Frontend::BootstrapParser.new(source, file: "grammar.y", mode: :extended).parse
      declaration = generated.declarations.fetch(0)

      assert_equal bootstrap.to_h, generated.to_h
      assert_instance_of Ibex::Frontend::AST::ParserConfiguration, declaration
      assert_equal %i[algorithm entries], declaration.settings.map(&:key)
      assert_equal [algorithm.to_sym, :shared], declaration.settings.map(&:value)
      assert_equal({ file: "grammar.y", line: 3, column: 3 }, declaration.settings.fetch(0).loc.to_h)
    end

    declaration = parse(grammar("entries isolated\n  algorithm lr1")).declarations.fetch(0)
    assert_equal %i[entries algorithm], declaration.settings.map(&:key)
  end

  def test_cst_trivia_is_a_parser_contract_setting
    source = <<~GRAMMAR
      class P
      pragma extended
      pragma cst
      parser
        cst_trivia balanced
      end
      rule
      start: TOKEN
      end
    GRAMMAR
    generated = parse(source)
    bootstrap = Ibex::Frontend::BootstrapParser.new(source, file: "grammar.y", mode: :extended).parse
    setting = generated.declarations.fetch(0).settings.fetch(0)

    assert_equal bootstrap.to_h, generated.to_h
    assert_equal :cst_trivia, setting.key
    assert_equal :balanced, setting.value
  end

  def test_cst_trivia_requires_the_stable_cst_pragma
    error = assert_raises(Ibex::Error) do
      Ibex::Normalizer.new(
        Ibex::Frontend::Parser.new(grammar("cst_trivia balanced"), file: "grammar.y", mode: :extended).parse,
        mode: :extended
      ).normalize
    end

    assert_equal "grammar.y:3:3: parser.cst_trivia requires pragma cst", error.message
  end

  def test_parser_declaration_is_extended_only_and_root_only
    error = assert_raises(Ibex::Error) do
      Ibex::Frontend::Parser.new(grammar("algorithm lalr"), file: "grammar.y").parse
    end
    assert_equal "grammar.y:2:1: parser declarations require extended mode", error.message

    source = "fragment\nparser\n  algorithm lalr\nend\nrule\nend\n"
    error = assert_raises(Ibex::Error) do
      Ibex::Frontend::Parser.new(source, file: "fragment.y", mode: :extended).parse_fragment
    end
    assert_equal "fragment.y:2:1: parser declarations are not allowed in fragments", error.message
  end

  def test_duplicate_unknown_and_invalid_settings_report_the_offending_token
    cases = {
      "algorithm lalr\n  algorithm lalr" =>
        "grammar.y:4:3: duplicate parser setting algorithm",
      "future lalr" => "grammar.y:3:3: unknown parser setting future",
      "algorithm future" =>
        "grammar.y:3:13: parser.algorithm must be one of slr, lalr, ielr, lr1; got future",
      "algorithm auto" =>
        "grammar.y:3:13: parser.algorithm must be one of slr, lalr, ielr, lr1; got auto",
      "entries future" =>
        "grammar.y:3:11: parser.entries must be one of shared, isolated; got future"
    }

    cases.each do |settings, message|
      error = assert_raises(Ibex::Error) { parse(grammar(settings)) }
      assert_equal message, error.message
    end
  end

  def test_formatter_preserves_the_lossless_block_and_is_idempotent
    source = "class P parser entries isolated algorithm ielr end start a b rule a:A;b:B end"
    expected = <<~GRAMMAR
      class P
      parser
        entries isolated
        algorithm ielr
      end
      start a b
      rule
        a : A;
        b : B
      end
    GRAMMAR

    formatted = Ibex::Frontend::Formatter.format(source, file: "grammar.y", mode: :extended)

    assert_equal expected, formatted
    assert_equal formatted, Ibex::Frontend::Formatter.format(formatted, file: "grammar.y", mode: :extended)
  end

  private

  def parse(source)
    Ibex::Frontend::Parser.new(source, file: "grammar.y", mode: :extended).parse
  end

  def grammar(settings)
    <<~GRAMMAR
      class P
      parser
        #{settings}
      end
      rule
      start: TOKEN
      end
    GRAMMAR
  end
end
