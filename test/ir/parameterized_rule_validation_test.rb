# frozen_string_literal: true

require_relative "../test_helper"

class IRParameterizedRuleValidationTest < Minitest::Test
  def test_rejects_duplicate_and_inconsistent_formals
    error = normalize_error("pair(X, X): X\nstart: pair(A, B)")
    assert_equal "parameter.y:4:1: duplicate parameter X in rule pair", error.message

    error = normalize_error("pair(X): X\npair(Y): Y\nstart: pair(A)")
    assert_equal(
      "parameter.y:5:1: parameterized rule pair uses inconsistent parameters (expected X, got Y)",
      error.message
    )
  end

  def test_accepts_repeated_definitions_with_identical_ordered_formals
    grammar = normalize("pair(X, Y): X Y\npair(X, Y): Y X\nstart: pair(A, B)")
    helper = grammar.nonterminals.find { |symbol| symbol.name.start_with?("$parameter_") }
    productions = grammar.productions.select { |production| production.lhs == helper.id }

    assert_equal 2, productions.length
  end

  def test_rejects_mixed_plain_and_parameterized_definitions
    error = normalize_error("list: ITEM\nlist(X): X\nstart: list(ITEM)")
    assert_equal "parameter.y:5:1: rule list has both plain and parameterized definitions", error.message

    error = normalize_error("list(X): X\nlist: ITEM\nstart: list(ITEM)")
    assert_equal "parameter.y:5:1: rule list has both plain and parameterized definitions", error.message
  end

  def test_rejects_terminal_collisions
    error = normalize_error("list(X): X\nstart: list(NUM)", declarations: "token list NUM\n")
    assert_equal "parameter.y:5:1: parameterized rule list collides with terminal list", error.message
  end

  def test_rejects_undefined_templates_wrong_arity_and_plain_use
    error = normalize_error("start: missing(NUM)")
    assert_equal "parameter.y:4:8: undefined parameterized rule missing", error.message

    error = normalize_error("pair(X, Y): X Y\nstart: pair(NUM)")
    assert_equal "parameter.y:5:8: parameterized rule pair expects 2 arguments, got 1", error.message

    error = normalize_error("list(X): X\nstart: list")
    assert_equal "parameter.y:5:8: parameterized rule list requires arguments", error.message
  end

  def test_rejects_formals_as_callees_and_named_references_inside_arguments
    error = normalize_error("apply(F, X): F(X)\nstart: apply(list, NUM)\nlist(X): X")
    assert_equal "parameter.y:4:14: formal F cannot be used as a parameterized rule name", error.message

    error = normalize_error("list(X): X\nstart: list(NUM:value)")
    assert_equal "parameter.y:5:13: named references are not allowed in parameter arguments", error.message
  end

  def test_rejects_complex_formal_precedence_arguments
    error = normalize_error("select(X): X = X\nstart: select((NUM))")
    assert_equal "parameter.y:4:12: formal precedence X requires one plain symbol argument", error.message
  end

  def test_templates_do_not_become_a_default_start_rule
    grammar = normalize("list(X): X\nstart: list(NUM)")
    assert_equal "start", grammar.start

    error = normalize_error("list(X): X")
    assert_equal "parameter.y:1:1: grammar has no start rule", error.message
  end

  def test_rejects_nonpositive_budget_options
    ast = parse("start: NUM")
    assert_raises(ArgumentError) { Ibex::Normalizer.new(ast, max_parameter_specializations: 0) }
    assert_raises(ArgumentError) { Ibex::Normalizer.new(ast, max_parameter_depth: 0) }
  end

  def test_argument_growing_recursion_reaches_a_high_configured_limit_without_using_the_ruby_stack
    error = assert_raises(Ibex::Error) do
      normalize(
        "grow(X): grow((X))\nstart: grow(NUM)",
        declarations: "token NUM\n",
        max_parameter_specializations: 2_500,
        max_parameter_depth: 2_000
      )
    end
    assert_equal "parameter.y:5:10: parameter expansion depth limit of 2000 exceeded", error.message
  end

  private

  def normalize_error(rules, declarations: "")
    assert_raises(Ibex::Error) { normalize(rules, declarations: declarations) }
  end

  def normalize(rules, declarations: "", **options)
    Ibex::Normalizer.new(parse(rules, declarations: declarations), mode: :extended, **options).normalize
  end

  def parse(rules, declarations: "")
    source = "class P\npragma extended\n#{declarations}rule\n#{rules}\nend\n"
    Ibex::Frontend::Parser.new(source, file: "parameter.y").parse
  end
end
