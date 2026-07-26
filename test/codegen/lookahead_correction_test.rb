# frozen_string_literal: true

require_relative "../test_helper"

class LookaheadCorrectionCodegenTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class GeneratedLAC
    rule
    start: TOKEN
    end
  GRAMMAR

  def test_extended_mode_enables_exact_expected_tokens
    parser_class = generate(mode: :extended)

    assert_equal true, parser_class.parser_tables.fetch(:exact_expected_tokens)
  end

  def test_compatible_mode_keeps_the_historical_expected_token_contract
    parser_class = generate(mode: :racc)

    refute parser_class.parser_tables.key?(:exact_expected_tokens)
  end

  private

  def generate(mode:)
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "lac.y", mode: mode).parse
    grammar = Ibex::Normalizer.new(ast, mode: mode).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    namespace = Module.new
    namespace.module_eval(Ibex::Codegen::Ruby.new(automaton).generate, "lac.rb")
    namespace.const_get(:GeneratedLAC)
  end
end
