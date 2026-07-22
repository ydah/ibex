# frozen_string_literal: true

require_relative "../test_helper"

class DefaultReductionsCodegenTest < Minitest::Test
  def test_plain_and_compact_parsers_use_defaults_without_delaying_errors
    %i[plain compact].each do |table|
      parser_class = generate_parser(default_reduction_source, "DefaultReductionParser", table)
      assert(parser_class::PARSER_TABLES.fetch(:default_actions).compact.any?)

      parser = parser_class.new
      error = assert_raises(Ibex::ParseError) { parser.parse_tokens([%i[A a], %i[BAD bad]]) }
      assert_includes error.message, "expected $eof, A, B, C"
      assert_empty parser.reductions

      parser = parser_class.new
      assert_raises(Ibex::ParseError) { parser.parse_tokens([%i[A a], %i[UNKNOWN bad]]) }
      assert_empty parser.reductions
      assert_equal %i[a b c], parser_class.new.parse_tokens([%i[A a], %i[B b], %i[C c]])
    end
  end

  def test_plain_and_compact_defaults_preserve_error_recovery
    %i[plain compact].each do |table|
      parser_class = generate_parser(default_recovery_source, "DefaultRecoveryParser", table)
      assert(parser_class::PARSER_TABLES.fetch(:default_actions).compact.any?)

      parser = parser_class.new
      tokens = [%i[BAD bad], [";", nil], %i[A a], [";", nil]]
      assert_equal %i[error a], parser.parse_tokens(tokens)
      assert_equal ["BAD"], parser.errors
    end
  end

  private

  def generate_parser(source, class_name, table)
    ast = Ibex::Frontend::Parser.new(source, file: "default_reductions.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton, table: table).generate
    container = Module.new
    container.module_eval(generated, "default_reductions.rb")
    container.const_get(class_name)
  end

  def default_reduction_source
    <<~GRAMMAR
      class DefaultReductionParser
      token A B C BAD
      rule
      start: list { result = val[0] }
      list: list item { result = val[0] + [val[1]] }
          | item { result = [val[0]] }
      item: A { result = val[0] }
          | B { result = val[0] }
          | C { result = val[0] }
      end
      ---- inner
      attr_reader :reductions
      def initialize = (super; @reductions = [])
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
      def on_reduce(production_id, _values, _result) = @reductions << production_id
    GRAMMAR
  end

  def default_recovery_source
    <<~GRAMMAR
      class DefaultRecoveryParser
      token A B C D E BAD ';'
      rule
      start: statements { result = val[0] }
      statements: statements statement { result = val[0] + [val[1]] }
                | statement { result = [val[0]] }
      statement: A ';' { result = :a }
               | B ';' { result = :b }
               | C ';' { result = :c }
               | D ';' { result = :d }
               | E ';' { result = :e }
               | error ';' { result = :error }
      end
      ---- inner
      attr_reader :errors
      def initialize = (super; @errors = [])
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
      def on_error(token_id, _value, _stack) = @errors << token_to_str(token_id)
    GRAMMAR
  end
end
