# frozen_string_literal: true

require_relative "../test_helper"

class CSTContractTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class CSTContractParser
    pragma extended
    %PRAGMA_CST%
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/ { lexeme.to_i }
      PLUS '+'
    end
    rule
    start: expression
    expression: NUM PLUS NUM { result = val[0] + val[2] }
    end
  GRAMMAR

  def test_cst_preserves_semantic_results_for_parse_do_parse_and_yyparse
    plain = generate(cst: false)
    syntax = generate(cst: true)

    assert_equal plain.new.parse("1 + 2"), syntax.new.parse("1 + 2")

    plain_pull = plain.new.lex("3 + 4")
    syntax_pull = syntax.new.lex("3 + 4")
    assert_equal plain_pull.do_parse, syntax_pull.do_parse
    assert_instance_of Ibex::Runtime::CST::SyntaxNode, syntax_pull.syntax_root

    tokens = [[:NUM, 5], [:PLUS, "+"], [:NUM, 6]]
    assert_equal yyparse(plain, tokens), yyparse(syntax, tokens)
  end

  def test_cst_preserves_hook_and_runtime_observer_order
    plain_timeline = timeline(generate(cst: false).new)
    syntax_timeline = timeline(generate(cst: true).new)

    assert_equal plain_timeline, syntax_timeline
  end

  def test_plain_tables_do_not_gain_cst_metadata
    tables = generate(cst: false).parser_tables

    refute tables.key?(:cst)
    refute tables.key?(:cst_start)
    refute tables.key?(:cst_trivia)
  end

  private

  def generate(cst:)
    pragma = cst ? "pragma cst" : ""
    source = SOURCE.sub("%PRAGMA_CST%", pragma)
    ast = Ibex::Frontend::Parser.new(source, file: "cst-contract.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    namespace = Module.new
    namespace.module_eval(Ibex::Codegen::Ruby.new(automaton).generate, "cst_contract_parser.rb")
    namespace.const_get(:CSTContractParser)
  end

  def yyparse(parser_class, tokens)
    source = Object.new
    source.define_singleton_method(:tokens) { |&block| tokens.each(&block) }
    parser_class.new.yyparse(source, :tokens)
  end

  def timeline(parser)
    result = []
    parser.observe do |event|
      result << [:event, event.type] unless event.type.to_s.start_with?("cst_")
    end
    parser.define_singleton_method(:on_shift) { |token_id, _value, _state| result << [:shift, token_id] }
    parser.define_singleton_method(:on_reduce) { |production_id, _values, _value| result << [:reduce, production_id] }
    parser.parse("1 + 2")
    result
  end
end
