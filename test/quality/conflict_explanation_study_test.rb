# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "json_schemer"
require "tmpdir"
require_relative "../../tool/quality/conflict_explanation_study"

# rubocop:disable Metrics/ClassLength -- adversarial evidence, blind review, and reveal gates share one fixture contract.
class ConflictExplanationStudyTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EVIDENCE = File.join(ROOT, "test/fixtures/conflict_explanations/study-v1.json")
  BLIND = File.join(ROOT, "docs/conflict-explanation-reviews/v1/blind-study-v1.json")
  REGISTRY = File.join(ROOT, "docs/conflict-explanation-review-status-v1.json")
  SCHEMA = File.join(ROOT, "schema/conflict-explanation-study-v1.schema.json")

  def test_committed_machine_corpus_is_closed_and_reproducible
    document = study.verify!

    assert_equal 4, document.dig("coverage", "case_count")
    assert_equal 5, document.dig("coverage", "conflict_count")
    assert_equal %w[reduce_reduce shift_reduce], document.dig("coverage", "conflict_types")
    assert_equal %w[nonunifying_witness unifying_counterexample], document.dig("coverage", "witness_kinds")
    assert_equal false, document.dig("capture", "executes_grammar_actions")
  end

  # rubocop:disable Metrics/AbcSize -- each assertion closes a distinct answer-leak or binding path.
  def test_blind_artifact_is_closed_deterministic_and_excludes_answer_fields
    document = blind_evidence

    assert_empty blind_schemer.validate(document).to_a
    assert_equal File.binread(BLIND), study.render_blind(evidence)
    assert_equal Digest::SHA256.file(EVIDENCE).hexdigest, document.fetch("source_study_sha256")
    assert_equal(
      Ibex::Quality::ConflictExplanationStudy::BLIND_CASE_IDS,
      document.fetch("cases").map { |entry| entry.fetch("blind_case_id") }
    )
    document.fetch("cases").each do |entry|
      assert_empty entry.keys & %w[id shape maintainer_hypothesis]
      assert_equal %w[bytes sha256], entry.fetch("grammar").keys.sort
    end
    changed = blind_evidence
    changed.fetch("cases").first["maintainer_hypothesis"] = { "cause" => "leaked answer" }
    refute_empty blind_schemer.validate(changed).to_a

    source = File.binread(BLIND)
    Ibex::Quality::ConflictExplanationStudy::CASES.each do |entry|
      refute_includes source, entry.fetch(:cause)
      refute_includes source, entry.fetch(:repair_goal)
      refute_includes source, "test/fixtures/conflict_explanations/#{entry.fetch(:path)}"
    end
  end
  # rubocop:enable Metrics/AbcSize

  def test_cases_cover_state_items_witnesses_and_suggested_repairs
    cases = evidence.fetch("cases").to_h { |entry| [entry.fetch("id"), entry] }

    assert_equal %w[H004-ELSE H004-EXPR H004-MERGE H004-RR], cases.keys.sort
    cases.each_value do |entry|
      entry.fetch("conflicts").each do |conflict|
        refute_empty conflict.fetch("state_items")
        assert_includes %w[unifying_counterexample nonunifying_witness],
                        conflict.dig("explanation", "witness", "kind")
        assert_search_evidence(conflict)
        assert conflict.fetch("repair").key?("proposals")
        assert conflict.fetch("repair").key?("advice")
      end
    end
    expression = cases.fetch("H004-EXPR").fetch("conflicts").first
    proposal = expression.dig("repair", "proposals", 0)
    assert_equal "declare right precedence for PLUS", proposal.fetch("description")
    assert_equal 1, proposal.dig("verification", "removed_conflicts")
  end

  def test_exhausted_conflict_search_is_inconclusive_instead_of_nonunifying
    source = File.binread(File.join(ROOT, "test/fixtures/conflict_explanations/expression.y"))
    ast = Ibex::Frontend::Parser.new(source, file: "expression.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    automaton = Ibex::LALR::Builder.new(grammar, algorithm: :lalr).build
    document = Ibex::Codegen::Explain.new(automaton, max_tokens: 16, max_configurations: 1).to_h
    witness = document.dig(:conflicts, 0, :witness)

    assert_equal "inconclusive", witness.fetch(:kind)
    assert_equal({ status: "exhausted", explored: 1, exhausted: true,
                   bounds: { max_tokens: 16, max_configurations: 1 } }, witness.fetch(:search))
  end

  def test_lalr_merge_is_nonunifying_and_precise_construction_removes_the_conflicts
    source = File.binread(File.join(ROOT, "test/fixtures/conflict_explanations/lalr_merge.y"))
    ast = Ibex::Frontend::Parser.new(source, file: "lalr_merge.y", mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    lalr = Ibex::LALR::Builder.new(grammar, algorithm: :lalr).build
    ielr = Ibex::LALR::Builder.new(grammar, algorithm: :ielr).build
    lr1 = Ibex::LALR::Builder.new(grammar, algorithm: :lr1).build

    assert_equal 2, lalr.conflict_summary.fetch(:rr)
    assert_equal 0, ielr.conflict_summary.fetch(:rr)
    assert_equal 0, lr1.conflict_summary.fetch(:rr)
    merge = evidence.fetch("cases").find { |entry| entry.fetch("id") == "H004-MERGE" }
    assert merge.fetch("conflicts").all? do |conflict|
      conflict.dig("explanation", "witness", "kind") == "nonunifying_witness"
    end
  end

  def test_subjective_gate_cannot_pass_without_independent_records
    changed = evidence
    changed.fetch("subjective_review")["status"] = "PASS"

    refute_empty schemer.validate(changed).to_a
    assert_equal "external_pending", evidence.dig("subjective_review", "status")
    assert_equal "docs/conflict-explanation-reviews/v1/blind-study-v1.json",
                 evidence.dig("subjective_review", "blind_artifact_path")
    assert_equal "docs/conflict-explanation-review-status-v1.json",
                 evidence.dig("subjective_review", "registry_path")
  end

  def test_schema_rejects_unknown_evidence_fields_and_unbounded_values
    changed = evidence
    changed.fetch("capture")["unknown"] = true
    refute_empty schemer.validate(changed).to_a

    changed = evidence
    changed.dig("capture", "search_bounds")["max_tokens"] = 0
    refute_empty schemer.validate(changed).to_a
  end

  def test_review_registry_is_bound_to_the_machine_and_blind_captures
    registry = review_registry
    registry["study_sha256"] = "0" * 64

    Dir.mktmpdir("ibex-h004-review") do |directory|
      path = File.join(directory, "review.json")
      File.binwrite(path, "#{JSON.pretty_generate(registry)}\n")
      error = assert_raises(RuntimeError) { study.verify!(review_path: path) }
      assert_includes error.message, "evidence digest drift"
    end

    registry = review_registry
    registry["blind_artifact_sha256"] = "0" * 64
    Dir.mktmpdir("ibex-h004-review") do |directory|
      path = write_json(directory, "review.json", registry)
      error = assert_raises(RuntimeError) { study.verify!(review_path: path) }
      assert_includes error.message, "blind artifact digest drift"
    end
  end

  def test_resigned_blind_artifact_tamper_is_rejected
    changed = blind_evidence
    changed.fetch("cases").first.fetch("automaton")["state_count"] += 1

    Dir.mktmpdir("ibex-h004-blind") do |directory|
      blind_path = write_json(directory, "blind.json", changed)
      registry = review_registry
      registry["blind_artifact_sha256"] = Digest::SHA256.file(blind_path).hexdigest
      review_path = write_json(directory, "review.json", registry)
      error = assert_raises(RuntimeError) do
        study.verify!(blind_path: blind_path, review_path: review_path)
      end
      assert_includes error.message, "blind artifact drift"
    end
  end

  def test_review_registry_rejects_case_insensitive_duplicate_reviewers
    registry = review_registry
    registry["status"] = "PASS"
    registry["review_phase"] = "review_complete"
    registry["reason"] = "claimed independent reviews"
    registry["records"] = [review_record("Example Reviewer", compared: true),
                           review_record("example reviewer", compared: true)]

    Dir.mktmpdir("ibex-h004-review") do |directory|
      path = File.join(directory, "review.json")
      File.binwrite(path, "#{JSON.pretty_generate(registry)}\n")
      error = assert_raises(RuntimeError) { study.verify!(review_path: path) }
      assert_includes error.message, "reviewer identities must be unique"
    end
  end

  def test_pass_requires_two_completed_post_reveal_comparisons
    registry = review_registry
    registry["status"] = "PASS"
    registry["review_phase"] = "review_complete"
    registry["reason"] = "comparison claimed before reveal completion"
    registry["records"] = [review_record("Reviewer One"), review_record("Reviewer Two")]

    Dir.mktmpdir("ibex-h004-review") do |directory|
      path = write_json(directory, "review.json", registry)
      error = assert_raises(RuntimeError) { study.verify!(review_path: path) }
      assert_includes error.message, "review registry violates its schema"
    end

    registry["records"] = [review_record("Reviewer One", compared: true),
                           review_record("Reviewer Two", compared: true)]
    Dir.mktmpdir("ibex-h004-review") do |directory|
      path = write_json(directory, "review.json", registry)
      assert_equal evidence, study.verify!(review_path: path)
    end
  end

  def test_reveal_comparison_must_retain_the_blind_to_source_mapping
    registry = review_registry
    registry["status"] = "PASS"
    registry["review_phase"] = "review_complete"
    registry["reason"] = "completed comparison with a changed mapping"
    registry["records"] = [review_record("Reviewer One", compared: true),
                           review_record("Reviewer Two", compared: true)]
    comparisons = registry.dig("records", 0, "reveal_comparison", "case_comparisons")
    comparisons[0]["study_case_id"], comparisons[1]["study_case_id"] =
      comparisons[1]["study_case_id"], comparisons[0]["study_case_id"]

    Dir.mktmpdir("ibex-h004-review") do |directory|
      path = write_json(directory, "review.json", registry)
      error = assert_raises(RuntimeError) { study.verify!(review_path: path) }
      assert_includes error.message, "reveal comparison mapping drift"
    end
  end

  private

  def assert_search_evidence(conflict)
    search = conflict.dig("explanation", "witness", "search")
    assert_includes %w[found not_found], search.fetch("status")
    refute search.fetch("exhausted")
    assert_operator search.fetch("explored"), :>, 0
    assert_equal evidence.dig("capture", "search_bounds"), search.fetch("bounds")
  end

  def study
    Ibex::Quality::ConflictExplanationStudy.new(root: ROOT)
  end

  def evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def blind_evidence
    JSON.parse(File.binread(BLIND))
  end

  def review_registry
    JSON.parse(File.binread(REGISTRY))
  end

  def schemer
    @schemer ||= JSONSchemer.schema(JSON.parse(File.binread(SCHEMA)))
  end

  def blind_schemer
    schema = JSON.parse(File.binread(SCHEMA))
    JSONSchemer.schema(schema.fetch("$defs").fetch("blind_artifact").merge("$defs" => schema.fetch("$defs")))
  end

  def review_record(reviewer, compared: false)
    {
      "reviewer" => reviewer,
      "reviewed_at" => "2026-08-05",
      "independent_of_implementation" => true,
      "blind_artifact_sha256" => Digest::SHA256.file(BLIND).hexdigest,
      "submitted_before_reveal" => true,
      "case_reviews" => Ibex::Quality::ConflictExplanationStudy::BLIND_CASE_IDS.map do |case_id|
        {
          "case_id" => case_id,
          "identified_cause" => "independent cause analysis",
          "chosen_edit" => "independent edit choice",
          "explanation_usefulness" => "useful",
          "repair_usefulness" => "unclear",
          "rationale" => "independent case rationale"
        }
      end,
      "reveal_comparison" => compared ? completed_reveal_comparison : { "status" => "pending" },
      "disagreement_summary" => "no disagreement recorded"
    }
  end

  def completed_reveal_comparison
    mappings = Ibex::Quality::ConflictExplanationStudy::BLIND_CASE_IDS.zip(
      Ibex::Quality::ConflictExplanationStudy::CASES.map { |entry| entry.fetch(:id) }
    )
    {
      "status" => "compared",
      "revealed_at" => "2026-08-05",
      "revealed_after_submission" => true,
      "study_sha256" => Digest::SHA256.file(EVIDENCE).hexdigest,
      "case_comparisons" => mappings.map do |blind_case_id, study_case_id|
        {
          "blind_case_id" => blind_case_id,
          "study_case_id" => study_case_id,
          "cause_alignment" => "unclear",
          "edit_alignment" => "unclear",
          "notes" => "comparison retained after reveal"
        }
      end
    }
  end

  def write_json(directory, name, value)
    path = File.join(directory, name)
    File.binwrite(path, "#{JSON.pretty_generate(value)}\n")
    path
  end
end
# rubocop:enable Metrics/ClassLength
