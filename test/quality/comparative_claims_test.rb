# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/comparative_claims"
require "tmpdir"
require "yaml"

class ComparativeClaimsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "docs/claims.yml")
  FIXTURES = File.join(ROOT, "test/fixtures/comparative_claims")

  def test_repository_claims_and_pending_evidence_bindings_are_valid
    assert Ibex::Quality::ComparativeClaims.new.verify!
  end

  def test_invalid_fixture_rejects_an_incomplete_comparison_set
    error = assert_raises(RuntimeError) { validator(File.join(FIXTURES, "invalid.yml")).verify! }
    assert_includes error.message, "canonical order"
  end

  def test_rejects_missing_evidence_and_nondeterministic_claim_order
    missing = document
    missing.fetch("claims").first.fetch("evidence").first["path"] = "docs/missing-evidence.md"
    assert_error(missing, "missing evidence")

    unordered = document
    unordered.fetch("claims").reverse!
    assert_error(unordered, "ordered deterministically")
  end

  def test_always_scans_readme_for_unmarked_strength_wording
    path = "test/fixtures/comparative_claims/invalid-unmarked.md"
    assert_error(document, "measured claim marker", readme: path)
  end

  def test_marker_must_contain_exact_wording_and_bound_table_text
    changed = document
    changed.fetch("claims").first["wording"] += " Extra scoped sentence."
    assert_error(changed, "exact registry wording")

    changed = document
    changed.fetch("claims").first.fetch("binding").fetch("required_text") << "missing case row"
    assert_error(changed, "missing bound evidence")
  end

  def test_pending_records_cannot_be_public_claims
    changed = document
    changed.fetch("claims").first.fetch("binding")["kind"] = "claim"
    assert_error(changed, "pending claims require an evidence binding")
  end

  def test_performance_record_cannot_be_promoted_without_the_result_artifact
    changed = document
    performance = changed.fetch("claims").last
    performance["state"] = "measured"
    performance.fetch("binding")["kind"] = "claim"
    performance["missing_evidence"] = []
    assert_error(changed, "require a result artifact")
  end

  def test_measured_claim_cannot_retain_pending_subjective_review
    changed = document
    error_ux = changed.fetch("claims").first
    error_ux["state"] = "measured"
    error_ux.fetch("binding")["kind"] = "claim"
    assert_error(changed, "invalid subjective review state")
  end

  def test_subject_and_corpus_identities_are_immutable
    changed = document
    changed.fetch("claims").first.fetch("subjects").first["revision"] = "main"
    assert_error(changed, "immutable 40- or 64-hex revision")

    changed = document
    changed.fetch("claims").first.fetch("subjects").last["revision"] = "a" * 40
    assert_error(changed, "release revision must be not_applicable")

    changed = document
    changed.fetch("claims").first.fetch("corpus").first["revision"] = "unknown"
    assert_error(changed, "immutable 40- or 64-hex revision")
  end

  def test_environment_rejects_missing_placeholder_and_unpublished_unknown_fields
    changed = document
    changed.fetch("claims").last.fetch("environment").fetch("unknown").delete("processors")
    assert_error(changed, "environment identity fields are missing")

    changed = document
    changed.fetch("claims").last.fetch("environment").fetch("known")["ruby_version"] = "TBD"
    assert_error(changed, "non-placeholder scalar")

    changed = document
    changed.fetch("claims").last.fetch("environment").fetch("unknown") << "ruby_version"
    changed.fetch("claims").last.fetch("environment").fetch("unknown").sort!
    changed.fetch("claims").last.fetch("environment").fetch("known").delete("ruby_version")
    assert_error(changed, "must be published in limitations")
  end

  def test_known_environment_must_appear_in_scoped_wording
    changed = document
    changed.fetch("claims").last.fetch("wording").sub!("Ruby 4.0.0", "the recorded Ruby")
    assert_error(changed, "must appear in scoped wording")
  end

  def test_public_command_is_an_unambiguous_executable_and_argv
    changed = document
    changed.fetch("claims").first["public_command"] = "bundle exec ruby tool/error_ux_snapshot.rb"
    assert_error(changed, "public_command must be a mapping")

    changed = document
    changed.fetch("claims").first.fetch("public_command")["executable"] = "bundle exec"
    assert_error(changed, "one argv token")

    changed = document
    changed.fetch("claims").first.fetch("public_command").fetch("argv") << "bad\0argument"
    assert_error(changed, "cannot contain NUL")
  end

  def test_rejects_score_and_ranking_variants
    phrases = [
      "aggregate scores", "combined score", "overall ranking", "total rankings",
      "rank table", "rankings", "総合点", "総合ランキング", "順位表", "合算スコア"
    ]
    phrases.each do |phrase|
      changed = document
      changed.fetch("claims").first["wording"] = "Forbidden #{phrase}"
      assert_error(changed, "combined scores and rankings are forbidden")
    end
  end

  def test_forbidden_term_allowance_is_limited_to_the_policy
    source = <<~MARKDOWN
      <!-- comparison-policy:forbidden-terms:start -->
      Do not publish an aggregate score or ranking.
      <!-- comparison-policy:forbidden-terms:end -->
    MARKDOWN
    Ibex::Quality::ComparativeWording.verify!(source, path: "policy", policy: true)
    error = assert_raises(RuntimeError) do
      Ibex::Quality::ComparativeWording.verify!(source, path: "README.md")
    end
    assert_includes error.message, "restricted to the comparison policy"
  end

  private

  def document
    YAML.safe_load(File.read(REGISTRY, encoding: Encoding::UTF_8), permitted_classes: [], aliases: false)
  end

  def validator(registry, readme: "README.md")
    Ibex::Quality::ComparativeClaims.new(root: ROOT, registry: registry, readme: readme)
  end

  def assert_error(value, message, readme: "README.md")
    error = verify_document_raises(value, readme: readme)
    assert_includes error.message, message
  end

  def verify_document_raises(value, readme: "README.md")
    Dir.mktmpdir("comparative-claims-test-") do |directory|
      path = File.join(directory, "claims.yml")
      File.write(path, YAML.dump(value))
      return assert_raises(RuntimeError) { validator(path, readme: readme).verify! }
    end
  end
end
