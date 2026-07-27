# frozen_string_literal: true

require_relative "../test_helper"

class CSTCharacterizationTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class CharacterizedCSTParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/ { lexeme.to_i }
      PLUS '+'
    end
    rule
    start: expression
    expression: term PLUS term
    term: NUM { result = val[0] * 10 }
    end
  GRAMMAR

  def test_action_values_are_separate_from_syntax_children
    result = generate.new.parse_with_syntax("1 + 2  ", file: "mixed.txt")
    start = result.syntax_root.children.fetch(0)
    expression = start.children.fetch(0)

    assert_equal 10, result.value
    assert_equal %w[term PLUS term], expression.children.map(&:symbol)
    assert(expression.children.values_at(0, 2).all?(Ibex::Runtime::CST::SyntaxNode))
    assert_equal "1 + 2  ", result.syntax_root.to_source
  end

  def test_pattern_matching_surface_is_stable
    tree = generate.new.parse_with_syntax("1 + 2").syntax_root.children.fetch(0)
    keys = tree.deconstruct_keys(nil)

    assert_equal tree.children, tree.deconstruct
    assert_equal :node, keys.fetch(:kind)
    assert_equal "start", keys.fetch(:symbol)
    assert_equal %i[kind symbol production_id children location trailing_trivia], keys.keys
  end

  private

  def generate
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "characterization.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    source = Ibex::Codegen::Ruby.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(source, "characterized_cst.rb")
    namespace.const_get(:CharacterizedCSTParser)
  end
end
