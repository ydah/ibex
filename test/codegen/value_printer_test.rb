# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"

class ValuePrinterCodegenTest < Minitest::Test
  SOURCE = <<~'GRAMMAR'
    class PrintedParser
    pragma extended
    %param offset "Integer"
    type NUM "Integer"
    type start "Integer"
    %printer NUM {
      @printer_calls = (@printer_calls || 0) + 1
      "number#{offset}=#{value}"
    }
    %printer start { "number#{offset}:result=#{value}" }
    rule
    start: NUM { result = val[0] + offset }
    end
    ---- inner
    attr_reader :printer_calls
    attr_writer :tokens
    def next_token = @tokens.shift
  GRAMMAR

  def test_generated_printers_are_lazy_and_cover_shift_and_reduce
    [false, true].each do |embedded|
      parser_class, = generate(embedded: embedded)
      ordinary = parser_class.new(offset: 1)
      ordinary.tokens = [[:NUM, 2]]
      assert_equal 3, ordinary.do_parse
      assert_nil ordinary.printer_calls

      output = StringIO.new
      traced = parser_class.new(offset: 1)
      traced.tokens = [[:NUM, 2]]
      traced.yydebug = true
      traced.yydebug_output = output
      assert_equal 3, traced.do_parse
      assert_equal 1, traced.printer_calls
      assert_includes output.string, "shift NUM value=number1=2"
      assert_includes output.string, "reduce 0 (1) value=number1:result=3"
    end
  end

  def test_programmatic_value_printer_overrides_generated_symbol_printers
    parser_class, = generate
    output = StringIO.new
    parser = parser_class.new(offset: 1)
    parser.tokens = [[:NUM, 2]]
    parser.yydebug = true
    parser.yydebug_output = output
    parser.trace_value_printer = ->(value) { "override=#{value}" }

    assert_equal 3, parser.do_parse
    assert_includes output.string, "shift NUM value=override=2"
    assert_includes output.string, "reduce 0 (1) value=override=3"
    assert_nil parser.printer_calls
  end

  def test_generated_printer_failures_do_not_change_parse_result
    source = <<~GRAMMAR
      class FailingPrinter
      pragma extended
      %printer NUM { raise "formatter failed" }
      rule
      start: NUM
      end
      ---- inner
      attr_writer :tokens
      def next_token = @tokens.shift
    GRAMMAR
    parser_class, = generate(source: source, class_name: :FailingPrinter)
    output = StringIO.new
    parser = parser_class.new
    parser.tokens = [[:NUM, 2]]
    parser.yydebug = true
    parser.yydebug_output = output

    assert_equal 2, parser.do_parse
    assert_includes output.string, "shift NUM value=<printer error: RuntimeError>"
  end

  def test_printer_methods_are_present_in_rbs_and_static_action_source
    _, automaton = generate
    signature = Ibex::Codegen::RBS.new(automaton).generate
    shadow = Ibex::Codegen::ActionSource.new(automaton).generate

    assert_match(/private def _ibex_value_printer_\d+: \(Integer value\) -> untyped/, signature)
    assert_match(/private def _ibex_value_printer_\d+\(value\)/, shadow)
    assert_includes shadow, "offset = @offset"
  end

  private

  def generate(embedded: false, source: SOURCE, class_name: :PrintedParser)
    ast = Ibex::Frontend::Parser.new(source, file: "printers.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    source = Ibex::Codegen::Ruby.new(automaton, embedded: embedded).generate
    namespace = Module.new
    namespace.module_eval(source, "printers.rb")
    [namespace.const_get(class_name), automaton]
  end
end
