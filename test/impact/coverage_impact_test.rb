# frozen_string_literal: true

require_relative "../test_helper"

class ImpactCoverageImpactTest < Minitest::Test
  def test_digest_mismatch_is_warned_and_excluded
    grammar = normalize("class P\ntoken TOKEN\nrule\nstart: TOKEN\nend\n")
    automaton = Ibex::LALR::Builder.new(grammar).build
    report = Ibex::Coverage::Report.new(
      grammar_digest: "sha256:#{'0' * 64}", table_format_version: 1,
      state_count: automaton.states.length, production_count: grammar.productions.length,
      sessions: 1, event_count: 1, state_hits: {}, production_hits: { 0 => 1 }
    )

    impact = Ibex::Impact::CoverageImpact.new(automaton, [0], [["coverage.json", report]])

    assert_equal "unmatched", impact.status
    assert_empty impact.reports
    assert_includes impact.warnings.first, "grammar digest does not match"
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact-coverage.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
