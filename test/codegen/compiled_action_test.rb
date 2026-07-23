# frozen_string_literal: true

require_relative "../test_helper"

class CompiledActionCodegenTest < Minitest::Test
  def test_mapped_action_method_is_compiled_once_with_exact_source_lines
    source = <<~GRAMMAR
      class CompiledActionParser
      rule
      start: TOKEN {
        if val.length == 1
          raise "compiled action failure"
        end
      }
      end
    GRAMMAR
    generated = generate(source, file: "compiled_action.y")

    assert_includes generated, "class_eval("
    refute_includes generated, "ACTION_CODE_"
    refute_match(/eval\s*\(.*binding/, generated)

    parser_class = evaluate(generated, "CompiledActionParser")
    parser = parser_class.new
    parser.define_singleton_method(:next_token) do
      next nil if @read

      @read = true
      [:TOKEN, nil]
    end
    error = assert_raises(RuntimeError) { parser.do_parse }
    assert_match(/\Acompiled_action\.y:5:/, error.backtrace.first)
  end

  def test_compiled_midrule_action_preserves_context_named_refs_and_result
    source = <<~GRAMMAR
      class CompiledMidruleParser
      pragma extended
      rule
      start: A:first { result = first * 2 } B:second { result = val[1] + second }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    parser_class = evaluate(generate(source), "CompiledMidruleParser")

    assert_equal 7, parser_class.new.parse_tokens([[:A, 2], [:B, 3]])
  end

  def test_no_result_var_action_can_return_in_mapped_and_direct_modes
    source = <<~GRAMMAR
      class ReturningActionParser
      options no_result_var
      rule
      start: TOKEN { return val[0] * 2 }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR

    [true, false].each do |line_convert|
      parser_class = evaluate(generate(source, line_convert: line_convert), "ReturningActionParser")
      assert_equal 6, parser_class.new.parse_tokens([[:TOKEN, 3]])
    end
  end

  private

  def generate(source, file: "compiled_action.y", **options)
    ast = Ibex::Frontend::Parser.new(source, file: file).parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    Ibex::Codegen::Ruby.new(automaton, **options).generate
  end

  def evaluate(source, class_name)
    namespace = Module.new
    namespace.module_eval(source, "compiled_action.rb")
    namespace.const_get(class_name)
  end
end
