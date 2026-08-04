# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/comparative_claims"
require "tmpdir"
require "yaml"

class ComparativeClaimsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "docs/claims.yml")
  FIXTURES = File.join(ROOT, "test/fixtures/comparative_claims")

  def test_repository_claims_and_public_markers_are_valid
    assert Ibex::Quality::ComparativeClaims.new.verify!
  end

  def test_invalid_fixture_rejects_an_incomplete_comparison_set
    error = assert_raises(RuntimeError) do
      validator(File.join(FIXTURES, "invalid.yml")).verify!
    end

    assert_includes error.message, "canonical order"
  end

  def test_rejects_missing_evidence_and_aggregate_scores
    missing = document
    missing.fetch("claims").first.fetch("evidence").first["path"] = "docs/missing-evidence.md"
    error = verify_document_raises(missing)
    assert_includes error.message, "missing evidence"

    scored = document
    scored.fetch("claims").first["wording"] = "An overall score of parser tools"
    error = verify_document_raises(scored)
    assert_includes error.message, "aggregate scores"
  end

  def test_rejects_nondeterministic_claim_order
    unordered = document
    unordered["claims"].reverse!

    error = verify_document_raises(unordered)
    assert_includes error.message, "ordered deterministically"
  end

  def test_rejects_unmarked_readme_strength_wording
    changed = document
    claim = changed.fetch("claims").find { |entry| entry.fetch("publication").fetch("path") == "README.md" }
    path = "test/fixtures/comparative_claims/invalid-unmarked.md"
    claim.fetch("publication")["path"] = path

    error = verify_document_raises(changed, readme: path)
    assert_includes error.message, "must be enclosed by a claim marker"
  end

  private

  def document
    YAML.safe_load(File.binread(REGISTRY), permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def validator(registry, readme: "README.md")
    Ibex::Quality::ComparativeClaims.new(root: ROOT, registry: registry, readme: readme)
  end

  def verify_document_raises(value, readme: "README.md")
    Dir.mktmpdir("comparative-claims-test-") do |directory|
      path = File.join(directory, "claims.yml")
      File.write(path, YAML.dump(value))
      return assert_raises(RuntimeError) { validator(path, readme: readme).verify! }
    end
  end
end
