# frozen_string_literal: true

require_relative "../test_helper"
require "ripper"

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
    assert_equal generated, Ibex::Codegen::Ruby.new(automaton, line_convert: true).generate
    assert_includes generated, "class_eval("
    namespace = Module.new
    namespace.module_eval(generated, "generated.rb")

    parser_class = namespace.const_get("HeredocParser")
    assert_equal "value=42\n", parser_class.new.parse_tokens([[:TOKEN, 42]])
  end

  def test_no_line_convert_preserves_plain_quoted_and_interpolated_heredoc_columns
    source = <<~'GRAMMAR'
      class DirectHeredocParser
      rule
      start: TOKEN {
        exact = <<EXACT
      exact #{val[0]}
      EXACT
        dedented = <<~"DYNAMIC }"
          dynamic #{val[0]}
        DYNAMIC }
        result = [exact, dedented]
      }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    automaton = build(source, file: "direct-heredoc.y")
    production = automaton.grammar.productions.fetch(0)
    generated = Ibex::Codegen::Ruby.new(automaton, line_convert: false).generate
    namespace = Module.new
    namespace.module_eval(generated, "direct-heredoc.rb")

    assert_equal heredoc_tokens(production.action.code), heredoc_tokens(generated)
    assert_includes generated, "\nEXACT\n"
    refute_includes generated, "\n  EXACT\n"
    parser_class = namespace.const_get("DirectHeredocParser")
    assert_equal ["exact 42\n", "dynamic 42\n"], parser_class.new.parse_tokens([[:TOKEN, 42]])
  end

  private

  def build(source, file:)
    ast = Ibex::Frontend::Parser.new(source, file: file).parse
    grammar = Ibex::Normalizer.new(ast).normalize
    Ibex::LALR::Builder.new(grammar).build
  end

  def heredoc_tokens(source)
    depth = 0
    Ripper.lex(source).filter_map do |_position, event, token, _state|
      if event == :on_heredoc_beg
        depth += 1
        [event, token]
      elsif event == :on_heredoc_end
        depth -= 1
        [event, token]
      elsif event == :on_tstring_content && depth.positive?
        [event, token]
      end
    end
  end
end
