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

  def test_action_values_are_children_of_actionless_reductions
    tree = generate.new.parse("1 + 2  ", file: "mixed.txt")
    expression = tree.children.fetch(0)

    assert(expression.children.all?(Ibex::Runtime::CST::Token))
    assert_equal %w[term PLUS term], expression.children.map(&:symbol)
    assert_equal [10, "+", 20], expression.children.map(&:value)
    assert_equal "start", tree.symbol
    assert_equal ["  "], tree.trailing_trivia.map(&:text)
  end

  def test_pattern_matching_surface_is_stable
    tree = generate.new.parse("1 + 2")
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
