# frozen_string_literal: true

require_relative "../test_helper"

class CodegenInlineRulesTest < Minitest::Test
  def test_composes_nested_repeated_actions_and_survives_ir_reload
    grammar = normalized_reloaded_grammar(nested_action_source)
    generated = Ibex::Codegen::Ruby.new(Ibex::LALR::Builder.new(grammar).build).generate
    parser_class = evaluate(generated, "InlineActions")
    first = { file: "input", line: 1, column: 1, end_column: 2 }
    second = { file: "input", line: 1, column: 3, end_column: 4 }
    tokens = [[:A, 1, first], [:B, 2, second], [:A, 3, first], [:B, 4, second]]
    result = parser_class.new.parse_tokens(tokens)

    assert_equal([[10, 2], [30, 4], 2],
                 result.map { |value| value.is_a?(Array) ? value.take(2) : value })
    assert_equal expected_span(1, 2), result.dig(0, 2)
    assert_equal expected_span(1, 4), result.dig(0, 3)
  end

  def test_preserves_implicit_empty_midrule_and_no_result_actions
    generated = generate(no_result_source, line_convert: false)
    parser_class = evaluate(generated, "InlineNoResult")

    assert_equal [[3, 6, 4], nil, :done],
                 parser_class.new.parse_tokens([[:A, 3], [:B, 4]])
  end

  def test_reconstructs_the_surrounding_value_stack_for_inline_actions
    source = <<~GRAMMAR
      class InlineStack
      pragma extended
      token A B
      rule
      %inline helper: B { result = [_values.last, val[0]] }
      start: A helper { result = val[1] }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    parser_class = evaluate(generate(source), "InlineStack")

    assert_equal 1, parser_class.new.parse_tokens([[:A, 1], [:B, 2]]).first
  end

  def test_yyaccept_in_an_inline_fragment_skips_later_fragments_and_the_caller
    parser_class = evaluate(generate(short_circuit_source("yyaccept", "InlineAccept")), "InlineAccept")
    parser = parser_class.new

    assert_equal :first, parser.parse_tokens([%i[A a], %i[B b]])
    assert_equal [:first], parser.events
  end

  def test_yyerror_in_an_inline_fragment_is_not_cancelled_by_yyerrok
    parser_class = evaluate(
      generate(short_circuit_source("yyerror; yyerrok", "InlineReject")),
      "InlineReject"
    )
    parser = parser_class.new

    assert_nil parser.parse_tokens([%i[A a], %i[B b]])
    assert_equal [:first], parser.events
  end

  private

  def generate(source, **options)
    grammar = normalized_reloaded_grammar(source)
    Ibex::Codegen::Ruby.new(Ibex::LALR::Builder.new(grammar).build, **options).generate
  end

  def normalized_reloaded_grammar(source)
    ast = Ibex::Frontend::Parser.new(source, file: "inline-actions.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    Ibex::IR::Serialize.load(Ibex::IR::Serialize.dump(grammar))
  end

  def evaluate(source, class_name)
    container = Module.new
    container.module_eval(source, "generated-inline.rb")
    container.const_get(class_name)
  end

  def expected_span(column, end_column)
    {
      file: "input", line: 1, column: column, end_file: "input", end_line: 1,
      end_column: end_column, empty: false
    }
  end

  def nested_action_source
    <<~GRAMMAR
      class InlineActions
      pragma extended
      token A B
      rule
      %inline atom: A:value { result = decorate(value) }
      %inline pair: atom:left B:right { result = [left, right, @1.to_h, @$.to_h] }
      start: pair:first pair:second { result = [first, second, val.length] }
      end
      ---- inner
      def decorate(value) = value * 10
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
  end

  def no_result_source
    <<~GRAMMAR
      class InlineNoResult
      pragma extended
      options no_result_var
      token A B
      rule
      %inline prefix: A { val[0] * factor } B { [val[0], val[1], val[2]] }
      %inline optional: | A
      start: prefix optional { [val[0], val[1], :done] }
      end
      ---- inner
      def factor = 2
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
  end

  def short_circuit_source(control, class_name)
    <<~GRAMMAR
      class #{class_name}
      pragma extended
      token A B
      rule
      %inline first: A { @events << :first; #{control}; result = :first }
      %inline second: B { @events << :second; result = :second }
      start: first second { @events << :caller; result = :caller }
      end
      ---- inner
      attr_reader :events
      def initialize = (super; @events = [])
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
  end
end
