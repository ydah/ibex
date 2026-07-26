# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/frontend/regenerator"

class FrontendShadowGrammarTest < Minitest::Test
  FIXTURES = %w[comprehensive.y extended.y edge.y parameterized.y].map do |name|
    File.expand_path("../fixtures/grammar/#{name}", __dir__)
  end.freeze
  SOURCES = [
    Ibex::Frontend::Regenerator::GRAMMAR_PATH,
    Ibex::Frontend::Regenerator::SHADOW_GRAMMAR_PATH,
    *FIXTURES
  ].freeze

  Object.class_eval(Ibex::Frontend::Regenerator.generate_shadow, "generated-shadow-parser.rb")
  SHADOW_PARSER = Ibex::Frontend::ShadowGeneratedParser

  def test_parameterized_inline_shadow_parser_matches_production_frontend
    SOURCES.each do |path|
      source = File.read(path)
      file = File.basename(path)

      assert_equal raw_generated(source, file: file).to_h, shadow_generated(source, file: file).to_h
    end
  end

  def test_shadow_grammar_exercises_parameterized_and_inline_lowering
    source = File.read(Ibex::Frontend::Regenerator::SHADOW_GRAMMAR_PATH)
    ast = Ibex::Frontend::BootstrapParser.new(
      source, file: Ibex::Frontend::Regenerator.relative_shadow_grammar_path, mode: :extended
    ).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize

    assert(grammar.productions.any? do |production|
      production.expansion&.dig(:parameter, :rule) == "sequence"
    end)
    assert(grammar.productions.any? { |production| production.action&.composition })
    refute grammar.symbol("sequence")
    refute grammar.symbol("literal_value")
  end

  private

  def raw_generated(source, file:)
    tokens = Ibex::Frontend::Lexer.new(source, file: file).tokenize
    Ibex::Frontend::GeneratedParser.new(tokens, mode: :extended).parse
  end

  def shadow_generated(source, file:)
    tokens = Ibex::Frontend::Lexer.new(source, file: file).tokenize
    SHADOW_PARSER.new(tokens, mode: :extended).parse
  end
end
