# frozen_string_literal: true

require_relative "../test_helper"
require "digest"
require "json"
require "stringio"
require "tmpdir"
require_relative "../../tool/quality/error_ux_round2"

class ErrorUXRound2QualityTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EVIDENCE = File.join(ROOT, "docs/error-ux-round2-v1.json")
  REVIEW_REGISTRY = File.join(ROOT, "docs/error-ux-round2-review-status-v1.json")
  R001 = File.join(ROOT, "test/fixtures/error_ux/json-errors-v1.json")

  def test_committed_h003_capture_is_current_and_truthfully_held
    output = StringIO.new

    assert Ibex::Quality::ErrorUXRound2.new(root: ROOT, output: output).verify!
    assert_includes output.string, "external subjective gate remains HOLD"
    assert_includes output.string, "external review registry is HOLD"
  end

  def test_r001_normative_snapshot_bytes_remain_unchanged
    assert_equal Ibex::ErrorUXRound2::R001_SNAPSHOT_SHA256, Digest::SHA256.hexdigest(File.binread(R001))
    assert_equal "bf49b2f8ba5329f1984d6e90e4b170b5811f4c800536fca56eba1f2725189dbf",
                 Ibex::ErrorUXRound2::R001_SNAPSHOT_SHA256
  end

  def test_schema_rejects_fabricated_external_review_and_open_lexer_reason
    changed = evidence
    changed.fetch("external_subjective_gate")["records"] << { "reviewer" => "fabricated" }
    assert_verification_error(changed, /violates schema/)

    changed = evidence
    lexer = case_for(changed, "lexer-failure")
    lexer.dig("observation", "diagnostics", 0, "expected_tokens")["reason"] = "unknown"
    assert_verification_error(changed, /violates schema/)
  end

  def test_dimension_coverage_tampering_is_rejected
    changed = evidence
    case_for(changed, "unknown-token").fetch("dimensions").replace(["delimiter-heavy"])

    assert_verification_error(changed, /dimension coverage drift/)
  end

  def test_multi_error_evidence_cannot_collapse_to_one_or_duplicate_a_location
    changed = evidence
    continuation = case_for(changed, "multi-error-continuation").fetch("observation")
    continuation.fetch("diagnostics").pop
    assert_verification_error(changed, /violates schema|at least two distinct diagnostics/)

    changed = evidence
    continuation = case_for(changed, "multi-error-continuation").fetch("observation")
    second = continuation.fetch("diagnostics").fetch(1)
    second.fetch("location")["start_byte"] = continuation.dig("diagnostics", 0, "location", "start_byte")
    assert_verification_error(changed, /at least two distinct diagnostics/)
  end

  def test_schema_rejects_fresh_acceptance_with_a_diagnostic
    changed = evidence
    accepted = changed.fetch("cases").find { |item| item.dig("fresh_reparse", "status") == "accepted" }
    accepted.fetch("fresh_reparse")["diagnostic"] = accepted.dig("observation", "diagnostics", 0)

    assert_verification_error(changed, /violates schema/)
  end

  def test_review_registry_rejects_stale_digest_case_inventory_and_empty_pass
    changed = review_registry
    changed.fetch("evidence")["sha256"] = "0" * 64
    assert_registry_error(changed, /evidence digest drift/)

    changed = review_registry
    changed.fetch("required_case_ids").pop
    assert_registry_error(changed, /violates schema|case inventory drift/)

    changed = review_registry
    changed["status"] = "PASS"
    changed["reason"] = "independent-reviews-published"
    assert_registry_error(changed, /violates schema/)
  end

  def test_review_registry_rejects_normalized_duplicate_reviewers
    changed = passing_registry(
      review_record("Alice Reviewer", "alice"),
      review_record("  Ａlice   Reviewer ", "alice-duplicate")
    )

    assert_registry_error(changed, /normalized reviewer identities must be unique/)
  end

  def test_review_registry_preserves_every_multi_reviewer_disagreement
    alice = review_record("Alice Reviewer", "alice")
    bob = review_record("Bob Reviewer", "bob", "H003-EOF-01" => "unclear")
    changed = passing_registry(alice, bob)
    assert_registry_error(changed, /disagreement inventory drift/)

    changed.fetch("disagreements") << {
      "case_id" => "H003-EOF-01",
      "reviewers" => ["Alice Reviewer", "Bob Reviewer"],
      "labels" => %w[useful unclear],
      "rationale" => "The reviewers reached different conclusions about the over-closing edit."
    }

    assert_registry_valid(changed)
  end

  private

  def evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def review_registry
    JSON.parse(File.binread(REVIEW_REGISTRY))
  end

  def passing_registry(*records)
    review_registry.merge(
      "status" => "PASS",
      "reason" => "independent-reviews-published",
      "records" => records,
      "disagreements" => []
    )
  end

  def review_record(name, suffix, labels = {})
    digest = Digest::SHA256.hexdigest(File.binread(EVIDENCE))
    {
      "record_id" => "H003R-2026-08-05-#{suffix}",
      "reviewer" => { "name" => name, "affiliation" => "External Review Lab", "relationship" => "external" },
      "reviewed_at" => "2026-08-05",
      "independent_of_implementation" => true,
      "publication_consent" => true,
      "evidence_sha256" => digest,
      "case_reviews" => review_registry.fetch("required_case_ids").map do |case_id|
        {
          "case_id" => case_id,
          "label" => labels.fetch(case_id, "useful"),
          "rationale" => "Independent assessment of the diagnostic and proposed edit.",
          "semantic_value_risk_assessment" => "The fresh parse does not establish author intent."
        }
      end,
      "overall_rationale" => "Independent assessment of all seven fixed cases."
    }
  end

  def case_for(document, dimension)
    document.fetch("cases").find { |item| item.fetch("dimensions").include?(dimension) }
  end

  def assert_verification_error(document, message)
    Dir.mktmpdir("ibex-h003-error-ux") do |directory|
      path = File.join(directory, "evidence.json")
      File.binwrite(path, "#{JSON.pretty_generate(document)}\n")
      error = assert_raises(RuntimeError) do
        Ibex::Quality::ErrorUXRound2.new(root: ROOT, evidence: path, output: StringIO.new).verify!
      end
      assert_match message, error.message
    end
  end

  def assert_registry_error(document, message)
    with_review_registry(document) do |path|
      error = assert_raises(RuntimeError) do
        verifier(review_registry: path).verify!
      end
      assert_match message, error.message
    end
  end

  def assert_registry_valid(document)
    with_review_registry(document) do |path|
      assert verifier(review_registry: path).verify!
    end
  end

  def with_review_registry(document)
    Dir.mktmpdir("ibex-h003-review") do |directory|
      path = File.join(directory, "review-status.json")
      File.binwrite(path, "#{JSON.pretty_generate(document)}\n")
      yield path
    end
  end

  def verifier(review_registry: REVIEW_REGISTRY)
    Ibex::Quality::ErrorUXRound2.new(
      root: ROOT, review_registry: review_registry, output: StringIO.new
    )
  end
end
