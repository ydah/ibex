# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"
require "tempfile"

class RubyCodegenTest < Minitest::Test
  def generate(source, file: "generated_source.y", **options)
    mode = options.delete(:mode) || :racc
    ast = Ibex::Frontend::Parser.new(source, file: file, mode: mode).parse
    grammar = Ibex::Normalizer.new(ast, mode: mode).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    Ibex::Codegen::Ruby.new(automaton, **options).generate
  end

  def calculator_source(class_name = "GeneratedCalc")
    <<~GRAMMAR
      class #{class_name}
      token NUM
      preclow
      left '+'
      left '*'
      prechigh
      rule
      expr: expr '+' expr { result = val[0] + val[2] }
          | expr '*' expr { result = val[0] * val[2] }
          | NUM { result = val[0] }
      end
      ---- inner
      def parse(tokens)
        @tokens = tokens
        do_parse
      end
      def next_token = @tokens.shift
    GRAMMAR
  end

  def evaluate(source, class_name, filename = "generated.rb")
    container = Module.new
    container.module_eval(source, filename)
    container.const_get(class_name)
  end

  def test_generated_compact_parser_calculates_with_precedence
    parser_class = evaluate(generate(calculator_source), "GeneratedCalc")
    tokens = [[:NUM, 2], ["+", nil], [:NUM, 3], ["*", nil], [:NUM, 4]]
    assert_equal 14, parser_class.new.parse(tokens)
  end

  def test_plain_parser_no_result_var_and_convert
    source = <<~GRAMMAR
      class ConvertedParser
      token NUM
      options no_result_var
      convert
      NUM ':number'
      end
      rule
      start: NUM { val[0].to_i }
      end
      ---- inner
      def parse(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    parser_class = evaluate(generate(source, table: :plain), "ConvertedParser")
    assert_equal 42, parser_class.new.parse([[:number, "42"]])
  end

  def test_user_code_placement_and_implicit_action_generation
    source = <<~GRAMMAR
      class UserCodeParser
      rule
      start: TOKEN
      end
      ---- header
      HEADER_MARK = true
      ---- inner
      def marker = HEADER_MARK
      ---- footer
      FOOTER_MARK = true
    GRAMMAR
    generated = generate(source, omit_action_call: false)
    parser_class = evaluate(generated, "UserCodeParser")
    assert parser_class.new.marker
    assert_includes generated, "private def _ibex_action_0"
    refute_match(/^\s+private :_ibex_action_/, generated)
    assert_operator generated.index("HEADER_MARK"), :<, generated.index("class UserCodeParser")
    assert_operator generated.index("FOOTER_MARK"), :>, generated.index("class UserCodeParser")
  end

  def test_generated_action_methods_are_private_without_changing_user_methods
    generated = generate(calculator_source)
    parser_class = evaluate(generated, "GeneratedCalc")
    action_methods = parser_class.private_instance_methods(false).grep(/\A_ibex_action_\d+\z/)

    assert_equal 3, action_methods.length
    assert_empty parser_class.public_instance_methods(false).grep(/\A_ibex_action_\d+\z/)
    assert_includes parser_class.public_instance_methods(false), :parse
    assert_includes parser_class.public_instance_methods(false), :next_token
    assert_equal 5, parser_class.new.parse([[:NUM, 2], ["+", nil], [:NUM, 3]])
  end

  def test_default_line_mapping_points_to_grammar
    source = "class FailingParser\nrule\nstart: TOKEN { raise 'boom' }\nend\n"
    parser_class = evaluate(generate(source, file: "failure.y"), "FailingParser")
    parser = parser_class.new
    parser.define_singleton_method(:next_token) do
      next nil if @read

      @read = true
      [:TOKEN, nil]
    end
    error = assert_raises(RuntimeError) { parser.do_parse }
    assert_match(/failure\.y:3/, error.backtrace.first)

    direct = generate(source, file: "failure.y", line_convert: false)
    refute_includes direct, "eval(ACTION_CODE_"
    assert_includes direct, "raise 'boom'"
  end

  def test_embedded_parser_runs_without_load_path
    source = calculator_source("EmbeddedCalc") + <<~FOOTER
      ---- footer
      tokens = [[:NUM, 2], ["+", nil], [:NUM, 5]]
      puts EmbeddedCalc.new.parse(tokens)
    FOOTER
    generated = generate(source, embedded: true)
    Tempfile.create(["embedded_parser", ".rb"]) do |file|
      file.write(generated)
      file.flush
      output, errors, status = Open3.capture3(RbConfig.ruby, "--disable-gems", file.path)
      assert status.success?, errors
      assert_equal "7\n", output
    end
  end

  def test_generated_source_has_no_ruby_warnings
    Tempfile.create(["generated_parser", ".rb"]) do |file|
      file.write(generate(calculator_source))
      file.flush
      _output, errors, status = Open3.capture3(RbConfig.ruby, "-wc", file.path)
      assert status.success?, errors
      assert_equal "", errors
    end
  end

  def test_extended_ebnf_value_conventions
    cases = [
      ["Optional", "ITEM?", [], nil],
      ["OptionalValue", "ITEM?", [[:ITEM, 1]], 1],
      ["Star", "ITEM*", [[:ITEM, 1], [:ITEM, 2]], [1, 2]],
      ["Plus", "ITEM+", [[:ITEM, 1], [:ITEM, 2]], [1, 2]],
      ["Separated", "separated_list(ITEM, ',')", [[:ITEM, 1], [",", nil], [:ITEM, 2]], [1, 2]],
      ["SeparatedNonempty", "separated_nonempty_list(ITEM, ',')", [[:ITEM, 1]], [1]]
    ]
    cases.each do |name, expression, tokens, expected|
      source = extended_parser_source("Ebnf#{name}", expression)
      parser_class = evaluate(generate(source, mode: :extended), "Ebnf#{name}")
      actual = parser_class.new.parse_tokens(tokens)
      expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
    end
  end

  def test_extended_named_references_bind_values
    source = <<~GRAMMAR
      class NamedParser
      rule
      start: NUM:left '+' NUM:right { result = left + right }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    parser_class = evaluate(generate(source, mode: :extended), "NamedParser")
    assert_equal 7, parser_class.new.parse_tokens([[:NUM, 3], ["+", nil], [:NUM, 4]])
  end

  def test_nested_grouped_ebnf_preserves_group_values
    source = <<~GRAMMAR
      class GroupedParser
      rule
      start: ((A B) | C)+
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    parser_class = evaluate(generate(source, mode: :extended), "GroupedParser")
    tokens = [[:A, 1], [:B, 2], [:C, 3], [:A, 4], [:B, 5]]
    assert_equal [[1, 2], 3, [4, 5]], parser_class.new.parse_tokens(tokens)
  end

  def test_separated_list_accepts_a_grouped_item
    source = <<~GRAMMAR
      class GroupedListParser
      rule
      start: separated_list((KEY VALUE), ',')
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    parser_class = evaluate(generate(source, mode: :extended), "GroupedListParser")
    tokens = [%i[KEY a], [:VALUE, 1], [",", nil], %i[KEY b], [:VALUE, 2]]
    assert_equal [[:a, 1], [:b, 2]], parser_class.new.parse_tokens(tokens)
  end

  private

  def extended_parser_source(class_name, expression)
    <<~GRAMMAR
      class #{class_name}
      rule
      start: #{expression}
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
  end
end
