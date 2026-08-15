# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class AnalysisNoExecTest < Minitest::Test
  def test_static_tools_do_not_execute_parser_or_lexer_actions_or_user_sections
    source = <<~GRAMMAR
      class NoExec
      pragma extended
      token TOKEN
      lexer
        TOKEN /token/ { raise "generated lexer action executed" }
      end
      rule
      start: TOKEN { raise "semantic action executed" }
      end
      ---- header
      raise "header executed"
      ---- inner
      raise "inner executed"
      ---- footer
      raise "footer executed"
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "no-exec.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize

    assert_equal [["TOKEN"]], Ibex::Samples.new(grammar).generate
    assert_equal "no_difference_within_bounds", Ibex::Fuzz.new(grammar, count: 2).run.fetch(:result)
  end

  def test_impact_command_keeps_actions_opaque
    source = <<~GRAMMAR
      class NoExecImpact
      token TOKEN
      rule
      start: TOKEN { raise "impact executed semantic action" }
      end
    GRAMMAR

    Dir.mktmpdir("ibex-impact-no-exec") do |directory|
      path = File.join(directory, "no-exec-impact.y")
      File.binwrite(path, source)
      output = StringIO.new

      status = Ibex::CLI.start(["impact", "--symbol=start", path], stdout: output, stderr: StringIO.new)

      assert_equal 0, status
      assert_includes output.string, '"mode": "potential"'
    end
  end
end
