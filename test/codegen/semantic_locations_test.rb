# frozen_string_literal: true

require_relative "../test_helper"

class SemanticLocationsCodegenTest < Minitest::Test
  def test_pull_yyparse_and_push_share_location_semantics
    [true, false].each do |line_convert|
      parser_class = build_parser(line_convert: line_convert)

      %i[pull yyparse push].each do |driver|
        first = { file: "#{driver}.txt", line: 1, column: 2 }
        second = { file: "#{driver}.txt", line: 1, column: 8, end_column: 9 }
        result = parse_with(parser_class, driver, first, second)

        assert_same first, result.fetch(:first)
        assert_same second, result.fetch(:second)
        assert_equal "@1 @$", result.fetch(:literal)
        assert_equal "1", result.fetch(:interpolated)
        assert_equal :ordinary_instance_variable, result.fetch(:ivar)

        inline_value = result.fetch(:inline_value)
        assert_same first, inline_value.fetch(0)
        assert_empty_span(inline_value.fetch(1), second)

        assert_empty_span(result.fetch(:inline), second)
        assert_span(result.fetch(:all), first, second)
      end
    end
  end

  def test_empty_production_uses_located_eof
    source = <<~GRAMMAR
      class EmptyLocationParser
      rule
      start: { result = @$ }
      end
      ---- inner
      def next_token = [nil, nil, { file: "empty.txt", line: 3, column: 5 }]
    GRAMMAR
    span = evaluate(generate(source), "EmptyLocationParser").new.do_parse

    assert span.empty?
    assert_equal({ file: "empty.txt", line: 3, column: 5 }, span.start)
    assert_same span.start, span.finish
  end

  def test_no_result_var_returns_locations_and_keeps_unlocated_tokens_nil
    source = <<~GRAMMAR
      class NoResultLocationParser
      options no_result_var
      rule
      start: TOKEN { [@1, @$] }
      end
      ---- inner
      attr_writer :tokens
      def next_token = @tokens.shift
    GRAMMAR

    [true, false].each do |line_convert|
      parser_class = evaluate(generate(source, line_convert: line_convert), "NoResultLocationParser")
      located = { file: "token.txt", line: 2, column: 4 }
      parser = parser_class.new
      parser.tokens = [[:TOKEN, :value, located]]
      token_location, reduction_location = parser.do_parse
      assert_same located, token_location
      assert_span(reduction_location, located, located)

      parser = parser_class.new
      parser.tokens = [%i[TOKEN value]]
      assert_equal [nil, nil], parser.do_parse
    end
  end

  private

  def build_parser(line_convert:)
    source = <<~'GRAMMAR'
      class SemanticLocationParser
      pragma extended
      rule
      start: A { result = { 0 => @1, 1 => @$ } } B {
        @memo = :ordinary_instance_variable
        result = {
          inline_value: val[1],
          first: @1,
          inline: @2,
          second: @3,
          all: @$,
          literal: "@1 @$",
          interpolated: "#{@1[:line]}",
          ivar: @memo
        }
      }
      end
      ---- inner
      attr_writer :tokens
      def next_token = @tokens.shift
    GRAMMAR
    evaluate(generate(source, line_convert: line_convert), "SemanticLocationParser")
  end

  def generate(source, **options)
    ast = Ibex::Frontend::Parser.new(source, file: "semantic-locations.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    Ibex::Codegen::Ruby.new(automaton, **options).generate
  end

  def evaluate(source, name)
    namespace = Module.new
    namespace.module_eval(source, "semantic-locations.rb")
    namespace.const_get(name)
  end

  def parse_with(parser_class, driver, first, second)
    tokens = [[:A, :a, first], [:B, :b, second]]
    parser = parser_class.new
    case driver
    when :pull
      parser.tokens = tokens
      parser.do_parse
    when :yyparse
      source = Object.new
      source.define_singleton_method(:tokens) { |&block| tokens.each(&block) }
      parser.yyparse(source, :tokens)
    when :push
      assert_equal :need_more, parser.push(:A, :a, first)
      assert_equal :need_more, parser.push(:B, :b, second)
      parser.finish
    end
  end

  def assert_empty_span(span, location)
    assert_instance_of Ibex::Runtime::LocationSpan, span
    assert span.empty?
    assert_same location, span.start
    assert_same location, span.finish
  end

  def assert_span(span, first, last)
    assert_instance_of Ibex::Runtime::LocationSpan, span
    refute span.empty?
    assert_same first, span.start
    assert_same last, span.finish
    assert_equal last.fetch(:end_column, last[:column]), span.end_column
  end
end
