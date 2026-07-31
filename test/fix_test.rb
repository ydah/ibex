# frozen_string_literal: true

require_relative "test_helper"

class FixTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class Ambiguous
    pragma extended
    expect 1
    rule
    start: expr
    expr: expr PLUS expr
        | NUM
    end
  GRAMMAR

  def test_only_candidates_passing_all_three_safety_conditions_are_proposed
    grammar, automaton = build(SOURCE)
    fixer = new_fixer(grammar, automaton)

    report = fixer.run

    assert_equal "proposals_found", report.fetch(:result)
    assert_equal Ibex::Fix::CATEGORIES.sort, report.fetch(:candidate_space).keys.sort
    assert_equal(["declare right precedence for PLUS"],
                 report.fetch(:proposals).map { |proposal| proposal.fetch(:description) })
    report.fetch(:proposals).each do |proposal|
      assert_equal "no_difference_within_bounds", proposal.dig(:equivalence, :result)
      assert_equal 1, proposal.dig(:side_effects, :removed_conflicts)
      assert_includes proposal.fetch(:unified_diff), "expect 0"
    end
    assert_includes report.fetch(:rejections).map { |entry| entry.fetch(:reason) },
                    "bounded_language_or_tree_difference"
  end

  def test_every_proposed_source_rebuilds_without_the_target_conflict
    grammar, automaton = build(SOURCE)
    fixer = new_fixer(grammar, automaton)
    report = fixer.run

    report.fetch(:proposals).select { |proposal| proposal.fetch(:applyable) }.each do |proposal|
      _candidate_grammar, candidate = build(fixer.sources.fetch(proposal.fetch(:id)))

      assert_equal 0, candidate.conflict_summary.fetch(:sr)
      assert_equal true, candidate.conflict_summary.fetch(:expectation_met)
    end
  end

  def test_candidate_enumeration_budget_is_distinct
    grammar, automaton = build(SOURCE)

    error = assert_raises(Ibex::Fix::BudgetExceeded) do
      new_fixer(grammar, automaton, max_candidates: 1).run
    end

    assert_equal "candidate_enumeration", error.details.fetch(:phase)
  end

  def test_independent_verifier_budget_exhaustion_is_not_reported_as_a_rejection
    grammar, automaton = build(SOURCE)

    error = assert_raises(Ibex::Fix::BudgetExceeded) do
      new_fixer(grammar, automaton, verify_max_items: 1).run
    end

    assert_equal "candidate_evaluation", error.details.fetch(:phase)
    assert_includes error.details.fetch(:rejections).map { |entry| entry.fetch(:reason) },
                    "verification_budget_exhausted"
  end

  def test_semantic_actions_are_not_executed
    source = SOURCE.sub("| NUM", '| NUM { raise "must not run" }')
    grammar, automaton = build(source)

    report = new_fixer(grammar, automaton, source: source).run

    assert_equal "proposals_found", report.fetch(:result)
  end

  def test_configured_message_catalog_impact_is_measured_against_the_original
    grammar, automaton = build(SOURCE)
    document = Ibex::ErrorMessages.parse(
      Ibex::ErrorMessages.render(automaton), file: "ambiguous.messages"
    )
    fixer = Ibex::Fix.new(
      SOURCE,
      file: "ambiguous.y", grammar: grammar, automaton: automaton,
      algorithm: :lalr, mode: :extended, equiv_samples: 10,
      equiv_max_tokens: 6, equiv_max_configurations: 1_000,
      messages: document, message_file: "ambiguous.messages"
    )

    impact = fixer.run.fetch(:proposals).fetch(0).dig(:side_effects, :message_catalog)

    assert_equal "evaluated", impact.fetch(:status)
    assert_equal "ambiguous.messages", impact.fetch(:file)
    assert_kind_of Array, impact.fetch(:moved)
    assert_kind_of Array, impact.fetch(:uncovered)
    assert_kind_of Array, impact.fetch(:unreachable)
  end

  private

  def new_fixer(grammar, automaton, source: SOURCE, max_candidates: 32, verify_max_items: 1_000_000)
    Ibex::Fix.new(
      source,
      file: "ambiguous.y", grammar: grammar, automaton: automaton,
      algorithm: :lalr, mode: :extended, max_candidates: max_candidates,
      equiv_samples: 10, equiv_max_tokens: 6, equiv_max_configurations: 1_000,
      verify_max_items: verify_max_items
    )
  end

  def build(source)
    ast = Ibex::Frontend::Parser.new(source, file: "ambiguous.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    [grammar, Ibex::LALR::Builder.new(grammar).build]
  end
end
