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
    term: NUM { (@action_trace ||= []) << val[0]; result = val[0] * 10 }
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
    tree = generate.new.parse_with_syntax("1 + 2  ").syntax_root.children.fetch(0)
    keys = tree.deconstruct_keys(nil)

    assert_equal tree.children, tree.deconstruct
    assert_equal tree.children, tree.to_a
    assert_equal :node, keys.fetch(:kind)
    assert_equal "start", keys.fetch(:symbol)
    assert_equal(-1, tree.production_id)
    assert_equal ["  "], tree.trailing_trivia.map(&:text)
    assert_predicate tree.trailing_trivia, :frozen?
    assert_equal %i[kind symbol production_id children location trailing_trivia], keys.keys
    assert_equal keys.keys, tree.to_h.keys
  end

  def test_token_compatibility_projection_preserves_the_pattern_surface
    token = generate.new.parse_with_syntax("1 + 2").syntax_root.first_token
    token_keys = token.deconstruct_keys(nil)

    assert_equal "1", token.value
    assert_equal token.green.leading, token.leading_trivia
    assert_empty token.children
    assert_equal %i[kind symbol value location leading_trivia], token_keys.keys
    assert_equal token_keys.keys, token.to_h.keys
  end

  def test_cst_does_not_change_semantic_results_or_action_order
    with_cst = generate.new
    without_cst = generate(SOURCE.sub("pragma cst\n", "pragma extended\n")).new

    syntax_result = with_cst.parse_with_syntax("1 + 2")
    semantic_result = without_cst.parse("1 + 2")

    assert_equal semantic_result, syntax_result.value
    assert_equal [1, 2], with_cst.instance_variable_get(:@action_trace)
    assert_equal(
      without_cst.instance_variable_get(:@action_trace),
      with_cst.instance_variable_get(:@action_trace)
    )
  end

  private

  def generate(source = SOURCE, mode: :default)
    ast = Ibex::Frontend::Parser.new(source, file: "characterization.y", mode: mode).parse
    grammar = Ibex::Normalizer.new(ast, mode: mode).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    source = Ibex::Codegen::Ruby.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(source, "characterized_cst.rb")
    namespace.const_get(grammar.class_name)
  end
end
