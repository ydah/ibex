# frozen_string_literal: true

require_relative "../test_helper"

class ActionScannerCodegenTest < Minitest::Test
  def test_quoted_heredoc_action_interpolates_at_parse_time
    source = <<~'GRAMMAR'
      class HeredocParser
      rule
      start: TOKEN {
        result = <<~"RESULT }"
          value=#{val[0]}
        RESULT }
      }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "heredoc.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(generated, "generated.rb")

    parser_class = namespace.const_get("HeredocParser")
    assert_equal "value=42\n", parser_class.new.parse_tokens([[:TOKEN, 42]])
  end
end
