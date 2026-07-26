# frozen_string_literal: true

require_relative "../test_helper"

class CSTCodegenTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class GeneratedCSTParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/ { lexeme.to_i }
      PLUS '+'
    end
    rule
    start: expression
    expression: NUM PLUS NUM
    end
  GRAMMAR

  def test_implicit_productions_build_an_immutable_lossless_tree
    parser_class = generate
    tree = parser_class.new.parse("1 + 2  ", file: "input.txt")
    expression = tree.children.fetch(0)
    tokens = expression.children

    assert_instance_of Ibex::Runtime::CST::Node, tree
    assert_equal "start", tree.symbol
    assert_equal "expression", expression.symbol
    assert_equal %w[NUM PLUS NUM], tokens.map(&:symbol)
    assert_equal [1, "+", 2], tokens.map(&:value)
    assert_equal [" "], tokens.fetch(1).leading_trivia.map(&:text)
    assert_equal [" "], tokens.fetch(2).leading_trivia.map(&:text)
    assert_equal ["  "], tree.trailing_trivia.map(&:text)
    assert_predicate tree, :frozen?
    assert_predicate expression.children, :frozen?
    assert_equal tokens, expression.deconstruct
    assert_equal "expression", expression.deconstruct_keys(nil).fetch(:symbol)
  end

  def test_drop_policy_discards_leading_and_trailing_trivia
    tree = generate(cst_trivia: :drop).new.parse("1 + 2  ")
    tokens = tree.children.fetch(0).children

    assert(tokens.all? { |token| token.leading_trivia.empty? })
    assert_empty tree.trailing_trivia
  end

  def test_lexical_and_syntax_failures_return_error_trees
    lexical = generate.new.parse("1 ? 2", file: "bad.txt")
    syntax = generate.new.parse("1 2", file: "bad.txt")

    assert_instance_of Ibex::Runtime::CST::Node, lexical
    assert_equal [:error], terminal_nodes(lexical).map(&:kind)
    assert_equal :lexical, terminal_nodes(lexical).first.reason
    assert_instance_of Ibex::Runtime::CST::Node, syntax
    assert_includes terminal_nodes(syntax).map(&:kind), :error
  end

  def test_bounded_repair_is_represented_by_missing_and_error_nodes
    parser = generate.new
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new(success_shifts: 1)
    tree = parser.parse("1 2")

    assert_includes terminal_nodes(tree).map(&:kind), :missing
    assert_includes terminal_nodes(tree).map(&:kind), :error
  end

  def test_mutated_examples_always_return_a_cst
    samples = mutations("1 + 2")
    samples.each do |sample|
      tree = generate.new.parse(sample, file: "fuzz.txt")
      assert_instance_of Ibex::Runtime::CST::Node, tree, sample.inspect
    end
  end

  private

  def generate(**options)
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "cst.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    source = Ibex::Codegen::Ruby.new(automaton, **options).generate
    namespace = Module.new
    namespace.module_eval(source, "generated_cst.rb")
    namespace.const_get(:GeneratedCSTParser)
  end

  def terminal_nodes(node)
    return [node] if node.is_a?(Ibex::Runtime::CST::Token)

    node.children.flat_map { |child| terminal_nodes(child) }
  end

  def mutations(source)
    values = ["", source]
    source.length.times do |index|
      values << source.dup.tap { |value| value.slice!(index) }
      values << source.dup.tap { |value| value[index] = "?" }
      values << source.dup.insert(index, "?")
    end
    values.uniq.freeze
  end
end
