# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../site/playground/analyzer"

class PlaygroundAnalyzerTest < Minitest::Test
  GRAMMAR = <<~GRAMMAR
    class BrowserParser
    token NUMBER
    rule
      expression : NUMBER
    end
  GRAMMAR

  def test_builds_automaton_document
    result = JSON.parse(IbexPlayground.analyze(GRAMMAR, "lalr"))

    assert result.fetch("ok")
    assert_equal "lalr1", result.fetch("algorithm")
    assert_operator result.dig("summary", "states"), :>, 0
    assert_equal "automaton", result.dig("automaton", "ibex_ir")
  end

  def test_reports_frontend_diagnostics_without_building
    result = JSON.parse(IbexPlayground.analyze("class Broken\nrule\n", "lalr"))

    refute result.fetch("ok")
    refute_empty result.fetch("diagnostics")
    refute result.key?("automaton")
  end

  def test_rejects_unknown_algorithms
    result = JSON.parse(IbexPlayground.analyze(GRAMMAR, "unknown"))

    refute result.fetch("ok")
    assert_match(/unsupported parser algorithm/, result.dig("diagnostics", 0, "message"))
  end

  def test_rejects_oversized_sources
    result = JSON.parse(IbexPlayground.analyze("x" * (IbexPlayground::MAX_SOURCE_BYTES + 1), "lalr"))

    refute result.fetch("ok")
    assert_match(/exceeds/, result.dig("diagnostics", 0, "message"))
  end
end
