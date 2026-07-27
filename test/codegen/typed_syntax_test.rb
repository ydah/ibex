# frozen_string_literal: true

require_relative "../test_helper"

class TypedSyntaxCodegenTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class TypedSyntaxParser
    pragma extended
    pragma cst
    token NUM PLUS COMMA
    type NUM "Integer"
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/ { lexeme.to_i }
      PLUS '+'
      COMMA ','
    end
    rule
    start: expression @node Root(value)
    expression: NUM PLUS NUM @node Addition(left, operator, right)
    list: separated_list(NUM, COMMA) @node NumberList(values)
    end
  GRAMMAR

  LIST_SOURCE = SOURCE.sub("start: expression @node Root(value)", "start: list @node Root(value)")
  ALTERNATIVE_SOURCE = <<~GRAMMAR
    class TypedSyntaxParser
    pragma extended
    pragma cst
    token NUM PLUS
    lexer
      NUM /[0-9]+/
      PLUS '+'
    end
    rule
    start: value @node Root(value)
    value: NUM @node Value(item)
         | grouped @node Value(item)
    grouped: PLUS
    end
  GRAMMAR

  def test_generated_views_cast_and_access_physical_slots
    parser_class, = generate(SOURCE)
    result = parser_class.new.parse_with_syntax("1 + 2")
    root_node = result.syntax_root.children.fetch(0)
    root = parser_class::Syntax::Root.cast(root_node)
    addition = parser_class::Syntax::Addition.cast(root.value)

    assert_instance_of parser_class::AST::Root, result.value
    assert_instance_of parser_class::Syntax::Root, root
    assert_instance_of parser_class::Syntax::Addition, addition
    assert_equal "1", addition.left.text
    assert_equal "+", addition.operator.text
    assert_equal "2", addition.right.text
    assert_equal root.value, root.deconstruct_keys(nil).fetch(:value)
    assert_equal "1 + 2", addition.to_source
    assert_nil parser_class::Syntax::Root.cast(addition.node)
  end

  def test_separated_list_views_enumerate_elements_and_separators
    parser_class, = generate(LIST_SOURCE)
    result = parser_class.new.parse_with_syntax("1, 2,3")
    root = parser_class::Syntax::Root.cast(result.syntax_root.children.fetch(0))
    list = parser_class::Syntax::NumberList.cast(root.value)

    assert_equal %w[1 2 3], list.each_element.map(&:text)
    assert_equal [",", ","], list.each_separator.map(&:text)
    assert_equal list.each_element.to_a, list.each_values_element.to_a
    assert_equal list.each_separator.to_a, list.each_values_separator.to_a
  end

  def test_generated_ruby_and_rbs_are_byte_stable
    parser_class, signature, ruby = generate(SOURCE)
    _, second_signature, second_ruby = generate(SOURCE)

    assert_equal ruby, second_ruby
    assert_equal signature, second_signature
    assert_includes ruby, "class Addition < Ibex::Runtime::CST::TypedNode"
    assert_includes ruby, "def operator = child_at_slot(1)"
    assert_includes signature, "module Syntax"
    assert_includes signature, "def self.cast: (Ibex::Runtime::CST::SyntaxNode node) -> Addition?"
    assert_includes signature, "def operator: () -> Ibex::Runtime::CST::SyntaxToken"
    assert_includes signature, "def value: () -> Ibex::Runtime::CST::SyntaxNode"
    assert parser_class.const_defined?(:Syntax, false)
  end

  def test_same_named_node_alternatives_follow_data_ast_shape_rules
    parser_class, signature, = generate(ALTERNATIVE_SOURCE)
    token_result = parser_class.new.parse_with_syntax("1")
    node_result = parser_class.new.parse_with_syntax("+")
    token_root = parser_class::Syntax::Root.cast(token_result.syntax_root.children.fetch(0))
    node_root = parser_class::Syntax::Root.cast(node_result.syntax_root.children.fetch(0))
    token_value = parser_class::Syntax::Value.cast(token_root.value)
    node_value = parser_class::Syntax::Value.cast(node_root.value)

    assert_instance_of Ibex::Runtime::CST::SyntaxToken, token_value.item
    assert_instance_of Ibex::Runtime::CST::SyntaxNode, node_value.item
    assert_includes(
      signature,
      "def item: () -> (Ibex::Runtime::CST::SyntaxToken | Ibex::Runtime::CST::SyntaxNode)"
    )
  end

  private

  def generate(source)
    ast = Ibex::Frontend::Parser.new(source, file: "typed_syntax.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    ruby = Ibex::Codegen::Ruby.new(automaton).generate
    signature = Ibex::Codegen::RBS.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(ruby, "typed_syntax.rb")
    [namespace.const_get(:TypedSyntaxParser), signature, ruby]
  end
end
