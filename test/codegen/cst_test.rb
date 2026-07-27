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

  def test_implicit_productions_build_an_immutable_lossless_tree # rubocop:disable Metrics/AbcSize
    parser_class = generate
    result = parser_class.new.parse_with_syntax("1 + 2  ", file: "input.txt")
    tree = result.syntax_root
    start = tree.children.fetch(0)
    expression = start.children.fetch(0)
    tokens = expression.children

    assert_equal 1, result.value
    assert_instance_of Ibex::Runtime::CST::SyntaxNode, tree
    assert_equal "source_file", tree.kind_name
    assert_equal "start", start.symbol
    assert_equal "expression", expression.symbol
    assert_equal %w[NUM PLUS NUM], tokens.map(&:kind_name)
    assert_equal ["1", "+", "2"], tokens.map(&:text)
    assert_equal [" "], tokens.fetch(1).green.leading.map(&:text)
    assert_equal [" "], tokens.fetch(2).green.leading.map(&:text)
    assert_equal ["  "], tree.last_token.green.leading.map(&:text)
    assert_equal "1 + 2  ", tree.to_source
    assert_equal tokens, expression.deconstruct
    assert_equal "expression", expression.deconstruct_keys(nil).fetch(:symbol)
  end

  def test_drop_policy_discards_leading_and_trailing_trivia
    tree = generate(cst_trivia: :drop).new.parse_with_syntax("1 + 2  ").syntax_root
    tokens = tree.tokens

    assert(tokens.all? { |token| token.green.leading.empty? && token.green.trailing.empty? })
    assert_equal "1+2", tree.to_source
    assert_raises(Ibex::Runtime::CST::TriviaDroppedError) { tree.span }
  end

  def test_lexical_and_syntax_failures_return_error_trees
    lexical = generate.new.parse_with_syntax("1 ? 2", file: "bad.txt")
    syntax = generate.new.parse_with_syntax("1 2", file: "bad.txt")

    assert_equal "1 ? 2", lexical.syntax_root.to_source
    assert_predicate lexical.syntax_root, :contains_error?
    assert_equal ["lexical_error_token"], terminal_nodes(lexical.syntax_root).map(&:kind_name).last(1)
    assert_equal "bad.txt", lexical.syntax_root.location.file
    assert_equal "1 2", syntax.syntax_root.to_source
    assert_predicate syntax.syntax_root, :contains_error?
    assert_equal 1, syntax.diagnostics.length
  end

  def test_bounded_repair_is_represented_by_missing_and_error_nodes
    parser = generate.new
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new(success_shifts: 1)
    result = parser.parse_with_syntax("1 2")
    tree = result.syntax_root

    assert_equal "1 2", tree.to_source
    assert terminal_nodes(tree).any?(&:missing?)
    assert_equal 1, result.diagnostics.length
  end

  def test_mutated_examples_always_return_a_cst
    samples = mutations("1 + 2")
    samples.each do |sample|
      tree = generate.new.parse_with_syntax(sample, file: "fuzz.txt").syntax_root
      assert_instance_of Ibex::Runtime::CST::SyntaxNode, tree, sample.inspect
      assert sample.b.start_with?(tree.to_source), sample.inspect
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
    node.tokens
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
