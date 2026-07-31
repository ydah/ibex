# frozen_string_literal: true

require_relative "test_helper"

class AnalysisNoExecTest < Minitest::Test
  def test_sentence_generation_and_fuzzing_do_not_execute_actions
    source = <<~GRAMMAR
      class NoExec
      rule
      start: TOKEN { raise "semantic action executed" }
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "no-exec.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize

    assert_equal [["TOKEN"]], Ibex::Samples.new(grammar).generate
    assert_equal "no_difference_within_bounds", Ibex::Fuzz.new(grammar, count: 2).run.fetch(:result)
  end
end
