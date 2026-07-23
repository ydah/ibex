# frozen_string_literal: true

require_relative "../test_helper"

class CodegenSymbolMetadataTest < Minitest::Test
  def test_display_names_reach_runtime_errors_and_token_names
    source = <<~GRAMMAR
      class DisplayParser
      pragma extended
      token NUM PLUS
      display NUM "number"
      display PLUS "+"
      rule
      start: NUM PLUS NUM
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "display.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton).generate
    container = Module.new
    container.module_eval(generated, "generated.rb")
    parser_class = container.const_get("DisplayParser")
    parser = parser_class.new
    parser.define_singleton_method(:next_token) { nil }

    error = assert_raises(Ibex::ParseError) { parser.do_parse }
    assert_match(/expected number/, error.message)
    assert_equal "number", parser_class::TOKEN_NAMES.fetch(2)
    assert_equal "+", parser_class::TOKEN_NAMES.fetch(3)
  end
end
