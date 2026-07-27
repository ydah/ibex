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

  RECOVERY_SOURCE = <<~GRAMMAR
    class CharacterizedRecoveryCSTParser
    pragma extended
    pragma cst
    start program
    token ITEM BAD SEMI
    %recover sync: SEMI
    lexer
      skip /[[:space:]]+/
      ITEM 'i'
      BAD 'x'
      SEMI ';'
    end
    rule
    program: statements
    statements: statements statement | statement
    statement: ITEM SEMI
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

  def test_legacy_action_overlay_root_trivia_and_token_values_are_characterized
    tree = without_warning { legacy(generate).new.parse("1 + 2  ", file: "mixed.txt") }
    expression = tree.children.fetch(0)

    assert_instance_of Ibex::Runtime::CST::Node, tree
    assert_equal "start", tree.symbol
    assert_equal ["  "], tree.trailing_trivia.map(&:text)
    assert(expression.children.all?(Ibex::Runtime::CST::Token))
    assert_equal %w[term PLUS term], expression.children.map(&:symbol)
    assert_equal [10, "+", 20], expression.children.map(&:value)
    assert_equal [" "], expression.children.fetch(1).leading_trivia.map(&:text)
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

  def test_legacy_pattern_matching_surface_is_characterized
    tree = without_warning { legacy(generate).new.parse("1 + 2") }
    keys = tree.deconstruct_keys(nil)

    assert_equal tree.children, tree.deconstruct
    assert_equal :node, keys.fetch(:kind)
    assert_equal "start", keys.fetch(:symbol)
    assert_equal %i[kind symbol production_id children location trailing_trivia], keys.keys
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

  def test_legacy_lexical_error_shape_is_characterized
    tree = without_warning { legacy(generate).new.parse("1 ? 2") }
    error = legacy_values(tree).grep(Ibex::Runtime::CST::Error).fetch(0)

    assert_instance_of Ibex::Runtime::CST::Node, tree
    assert_equal "start", tree.symbol
    assert_equal :lexical, error.reason
    assert_equal "lexer input", error.symbol
  end

  def test_legacy_missing_token_shape_is_characterized
    parser = legacy(generate).new
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new(success_shifts: 1)
    tree = without_warning { parser.parse("1 2") }
    missing = legacy_values(tree).grep(Ibex::Runtime::CST::Missing)

    refute_empty missing
    assert_equal :missing, missing.fetch(0).kind
    assert_equal "PLUS", missing.fetch(0).symbol
  end

  def test_legacy_recovery_shape_is_characterized
    parser_class = generate(RECOVERY_SOURCE, mode: :extended)
    tree = without_warning { legacy(parser_class).new.parse("i x x; i;") }
    errors = legacy_values(tree).grep(Ibex::Runtime::CST::Error)

    refute_empty errors
    assert(errors.any? { |error| %i[discard syntax].include?(error.reason) })
    assert_equal "program", tree.symbol
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

  def legacy(parser_class)
    current = parser_class.parser_tables
    kinds = current.fetch(:cst).fetch(:kinds)
    start_kind = kinds.fetch(:nonterminal_range).fetch(0)
    tables = current.merge(
      format_version: 5,
      cst: true,
      cst_start: kinds.fetch(:names).fetch(start_kind),
      cst_trivia: :attach,
      symbol_names: kinds.fetch(:names)
    ).freeze
    Class.new(parser_class).tap do |legacy_class|
      legacy_class.define_singleton_method(:parser_tables) { tables }
    end
  end

  def without_warning
    value = nil
    capture_io { value = yield }
    value
  end

  def legacy_values(value)
    return [value] unless value.is_a?(Ibex::Runtime::CST::Node)

    [value] + value.children.flat_map { |child| legacy_values(child) }
  end
end
