# frozen_string_literal: true

require_relative "../test_helper"
require "json"

class CSTRuntimeIntegrationTest < Minitest::Test # rubocop:disable Metrics/ClassLength -- one golden spans all paths.
  GOLDEN_PATH = File.expand_path("../fixtures/cst/runtime-paths-v1.json", __dir__)

  BALANCED_SOURCE = <<~GRAMMAR
    class BalancedCSTParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/
      PLUS '+'
    end
    rule
    start: NUM PLUS NUM
    end
  GRAMMAR

  MULTIPLE_ENTRY_SOURCE = <<~GRAMMAR
    class MultipleEntryCSTParser
    pragma extended
    pragma cst
    start program expression
    token A B
    lexer
      skip /[[:space:]]+/
      A 'a'
      B 'b'
    end
    rule
    program: A B
    expression: A
    end
  GRAMMAR

  EARLY_ACCEPT_SOURCE = <<~GRAMMAR
    class EarlyAcceptCSTParser
    pragma cst
    token A B
    lexer
      skip /[[:space:]]+/
      A 'a'
      B 'b'
    end
    rule
    start: A { yyaccept } B
    end
  GRAMMAR

  RECOVERY_SOURCE = <<~GRAMMAR
    class RecoveringCSTParser
    pragma extended
    pragma cst
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

  YACC_RECOVERY_SOURCE = <<~GRAMMAR
    class YaccRecoveringCSTParser
    pragma cst
    token ITEM BAD SEMI
    lexer
      skip /[[:space:]]+/
      ITEM 'i'
      BAD 'x'
      SEMI ';'
    end
    rule
    program: statements
    statements: statements statement | statement
    statement: ITEM SEMI | error SEMI
    end
  GRAMMAR

  def test_balanced_trivia_splits_at_the_first_newline
    tree = generate(BALANCED_SOURCE, cst_trivia: :balanced).new.parse_with_syntax("1 \n  + 2").syntax_root
    number, plus, = tree.tokens

    assert_equal [" \n"], number.green.trailing.map(&:text)
    assert_equal ["  "], plus.green.leading.map(&:text)
    assert_equal "1 \n  + 2", tree.to_source
  end

  def test_each_entry_builds_an_independent_source_file_root
    parser_class = generate(MULTIPLE_ENTRY_SOURCE, mode: :extended)
    program = parser_class.new
    expression = parser_class.new

    program.lex("a b")
    program.parse_program
    expression.lex("a")
    expression.parse_expression

    assert_equal "program", program.syntax_root.children.fetch(0).symbol
    assert_equal "a b", program.syntax_root.to_source
    assert_equal "expression", expression.syntax_root.children.fetch(0).symbol
    assert_equal "a", expression.syntax_root.to_source
    refute_same program.syntax_root.green, expression.syntax_root.green
  end

  def test_early_accept_marks_the_consumed_prefix_incomplete
    tree = generate(EARLY_ACCEPT_SOURCE).new.parse_with_syntax("a b").syntax_root

    assert_equal "a", tree.to_source
    assert_predicate tree, :incomplete_input?
  end

  def test_recovery_pop_and_panic_discard_preserve_source_bytes
    result = generate(RECOVERY_SOURCE, mode: :extended).new.parse_with_syntax("i x x; i;")

    assert_equal "i x x; i;", result.syntax_root.to_source
    assert result.syntax_root.green.flags.anybits?(Ibex::Runtime::CST::Flags::CONTAINS_SKIPPED)
    assert_operator result.diagnostics.length, :>=, 1
  end

  def test_format_five_tables_keep_the_legacy_cst_path
    parser_class = generate(BALANCED_SOURCE)
    current = parser_class.parser_tables
    legacy = current.merge(
      format_version: 5,
      cst: true,
      cst_start: "start",
      cst_trivia: :attach,
      symbol_names: current.fetch(:cst).fetch(:kinds).fetch(:names)
    ).freeze
    legacy_class = Class.new(parser_class)
    legacy_class.define_singleton_method(:parser_tables) { legacy }

    tree = nil
    _stdout, stderr = capture_io do
      parser = legacy_class.new
      tree = parser.parse("1 + 2 ")
      parser.parse("3 + 4")
    end

    assert_instance_of Ibex::Runtime::CST::Node, tree
    assert_equal "start", tree.symbol
    assert_equal [" "], tree.trailing_trivia.map(&:text)
    assert_equal 1, stderr.scan("legacy format-v1-v5 CST values are deprecated").length
  end

  def test_error_and_trivia_paths_match_the_golden_snapshot
    actual = runtime_path_snapshot
    if ENV["PRINT_IBEX_CST_RUNTIME_PATHS"] == "1"
      puts JSON.pretty_generate(actual)
      skip "printed the candidate runtime-path snapshot"
    end

    assert_equal JSON.parse(File.binread(GOLDEN_PATH)), actual
  end

  private

  def generate(source, cst_trivia: :leading, mode: :default)
    ast = Ibex::Frontend::Parser.new(source, file: "integration.y", mode: mode).parse
    grammar = Ibex::Normalizer.new(ast, mode: mode).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton, cst_trivia: cst_trivia).generate
    namespace = Module.new
    namespace.module_eval(generated, "generated_cst_integration.rb")
    namespace.const_get(grammar.class_name)
  end

  def runtime_path_snapshot # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    insertion_parser = generate(BALANCED_SOURCE).new
    insertion_parser.repair_policy = Ibex::Runtime::RepairPolicy.new(success_shifts: 1)
    deletion_parser = generate(BALANCED_SOURCE).new
    deletion_parser.repair_policy = Ibex::Runtime::RepairPolicy.new(success_shifts: 1)
    replacement_parser = generate(BALANCED_SOURCE).new
    replacement_parser.repair_policy = Ibex::Runtime::RepairPolicy.new(
      insert_cost: 5, delete_cost: 5, replace_cost: 1, max_cost: 1, success_shifts: 1
    )
    recovery_parser = generate(RECOVERY_SOURCE, mode: :extended).new
    yacc_recovery_parser = generate(YACC_RECOVERY_SOURCE).new
    yacc_recovery_parser.define_singleton_method(:on_error) { |_token_id, _value, _value_stack| nil }
    cases = {
      "lexical_failure" => generate(BALANCED_SOURCE).new.parse_with_syntax("1 ? 2"),
      "repair_insertion" => insertion_parser.parse_with_syntax("1 2"),
      "repair_deletion" => deletion_parser.parse_with_syntax("1 + + 2"),
      "repair_replacement" => replacement_parser.parse_with_syntax("1 + +"),
      "yacc_recovery_pop" => yacc_recovery_parser.parse_with_syntax("i x; i;"),
      "panic_discard" => recovery_parser.parse_with_syntax("i x x; i;"),
      "unrecoverable" => generate(BALANCED_SOURCE).new.parse_with_syntax("1"),
      "early_accept" => generate(EARLY_ACCEPT_SOURCE).new.parse_with_syntax("a b")
    }
    error_paths = cases.transform_values do |result|
      {
        "source" => result.syntax_root.source_text.text,
        "reconstructed" => result.syntax_root.to_source,
        "diagnostic_count" => result.diagnostics.length,
        "tree" => syntax_snapshot(result.syntax_root)
      }
    end
    trivia_source = "1 \n  + 2 "
    trivia_paths = %i[leading balanced drop].to_h do |policy|
      tree = generate(BALANCED_SOURCE, cst_trivia: policy).new.parse_with_syntax(trivia_source).syntax_root
      [
        policy.to_s,
        {
          "source" => trivia_source,
          "reconstructed" => tree.to_source,
          "tokens" => tree.tokens.map { |token| syntax_snapshot(token) }
        }
      ]
    end
    { "error_paths" => error_paths, "trivia_paths" => trivia_paths }
  end

  def syntax_snapshot(element)
    snapshot = {
      "kind" => element.kind_name,
      "flags" => element.green.flags
    }
    if element.is_a?(Ibex::Runtime::CST::SyntaxNode)
      snapshot["children"] = element.children.map { |child| syntax_snapshot(child) }
    else
      snapshot["text"] = element.text
      snapshot["expected_kind"] = element.green.expected_kind
      snapshot["leading"] = element.green.leading.map { |trivia| [trivia.kind, trivia.text] }
      snapshot["trailing"] = element.green.trailing.map { |trivia| [trivia.kind, trivia.text] }
    end
    snapshot
  end
end
