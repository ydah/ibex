# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/maturity"
require "date"
require "tmpdir"
require "yaml"

# -- one adversarial suite mutates every closed maturity evidence family.
class MaturityTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "docs/maturity.yml")
  NARRATIVE = File.join(ROOT, "docs/maturity.md")
  TODAY = Date.new(2026, 8, 4)

  def test_repository_inventory_evidence_and_public_summaries_are_valid
    assert Ibex::Quality::Maturity.new(today: TODAY).verify!
  end

  def test_rejects_a_missing_duplicate_or_reordered_feature
    changed = document
    changed.fetch("features").pop
    assert_error(changed, "exact 18 Preview + 2 Experimental")

    changed = document
    changed.fetch("features")[1]["id"] = changed.fetch("features").first.fetch("id")
    assert_error(changed, "unique identifiers")

    changed = document
    changed.fetch("features").rotate!
    assert_error(changed, "exact 18 Preview + 2 Experimental")
  end

  def test_rejects_silent_maturity_changes_and_promotion_without_release_evidence
    changed = document
    feature(changed, "ielr")["maturity"] = "stable"
    assert_error(changed, "silent promotion or removal")

    changed = document
    decision = feature(changed, "ielr").fetch("decision")
    decision["outcome"] = "promote"
    decision["target_maturity"] = "stable"
    assert_error(changed, "promotion requires met criteria")

    changed = document
    decision = feature(changed, "ielr").fetch("decision")
    decision["outcome"] = "promote"
    decision["target_maturity"] = "stable"
    decision["criteria_status"] = "met"
    assert_error(changed, "forbidden before R001 and exact-revision R002")
  end

  def test_rejects_synthetic_or_diagnostic_evidence_as_external_use
    changed = document
    use = feature(changed, "generated-lexers").fetch("external_use")
    use["status"] = "demonstrated"
    assert_error(changed, "cannot prove external use")

    changed = document
    use = feature(changed, "semantic-locations-types").fetch("external_use")
    use["status"] = "demonstrated"
    assert_error(changed, "cannot prove external use")

    changed = document
    use = feature(changed, "lsp").fetch("external_use")
    use["status"] = "demonstrated"
    assert_error(changed, "requires workload IDs")

    changed = document
    use = feature(changed, "lsp").fetch("external_use")
    use["status"] = "demonstrated"
    use["workload_ids"] = ["bcdice-command-parser"]
    assert_error(changed, "do not bind the claimed feature use")
  end

  def test_rejects_missing_documentation_tooling_limitations_and_review_triggers
    changed = document
    feature(changed, "lsp").dig("documentation", "evidence").clear
    assert_error(changed, "documentation evidence must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("documentation", "gaps").clear
    assert_error(changed, "documentation gaps must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("dependent_tooling", "evidence").clear
    assert_error(changed, "tooling evidence must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("dependent_tooling", "gaps").clear
    assert_error(changed, "tooling gaps must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("limitations", "performance").clear
    assert_error(changed, "performance limitations must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("limitations", "safety").clear
    assert_error(changed, "safety limitations must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("next_review", "triggers").clear
    assert_error(changed, "next review triggers must be a non-empty")
  end

  def test_rejects_stale_incomplete_or_unknown_issue_audits
    changed = document
    changed.dig("audit", "issue_audits", 0)["fresh_until"] = "2026-08-03"
    assert_error(changed, "issue audit is stale")

    changed = document
    changed.dig("audit", "issue_audits", 0, "result")["status"] = "unknown"
    assert_error(changed, "result status must be complete")

    changed = document
    changed.dig("audit", "issue_audits", 0, "result")["incomplete_results"] = true
    assert_error(changed, "incomplete GitHub issue results")

    changed = document
    feature(changed, "debug")["issue_audit"]["status"] = "unknown"
    assert_error(changed, "must be none_found or open_found")
  end

  def test_rejects_unexplained_history_and_implementation_only_decisions
    changed = document
    feature(changed, "watch").dig("specification_history", "unknowns").clear
    assert_error(changed, "unreconstructed history requires an explicit unknown")

    changed = document
    feature(changed, "watch")["decision"]["reason"] = "The implementation exists."
    assert_error(changed, "implementation existence cannot be the reason")
  end

  def test_rejects_wrong_feature_budget_or_release_dependency_state
    changed = document
    changed.fetch("budgets")["experimental_product_features"] = 1
    assert_error(changed, "budgets do not match")

    changed = document
    changed.dig("release_dependencies", "R002")["status"] = "complete"
    assert_error(changed, "R002 dependency status drift")

    changed = document
    feature(changed, "bounded-repair").dig("release_gate", "blockers").delete("R001")
    assert_error(changed, "release blockers must be exactly R001 and R002")
  end

  def test_rejects_missing_evidence_and_source_digest_drift
    changed = document
    feature(changed, "coverage").dig("documentation", "evidence")[0] = "docs/missing.md"
    assert_error(changed, "path is missing")

    changed = document
    feature(changed, "coverage").dig("sources", 0)["sha256"] = "0" * 64
    assert_error(changed, "source digest drift")
  end

  def test_rejects_hidden_redesign_or_removal_when_public_summary_is_unchanged
    %w[redesign remove].each do |outcome|
      changed = document
      feature(changed, "browser-playground")["decision"]["outcome"] = outcome
      assert_error(changed, "maturity summary drift")
    end
  end

  def test_rejects_narrative_or_stability_summary_drift
    Dir.mktmpdir("maturity-narrative-test-") do |directory|
      narrative = File.join(directory, "maturity.md")
      File.write(narrative, File.read(NARRATIVE).sub("`ebnf-groups`", "`ebnf-group`"))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Maturity.new(narrative: narrative, today: TODAY).verify!
      end
      assert_includes error.message, "maturity summary drift"
    end

    Dir.mktmpdir("maturity-stability-test-") do |directory|
      stability = File.join(directory, "stability.md")
      source = File.read(File.join(ROOT, "docs/stability.md")).sub("Keep Experimental", "Retain Experimental")
      File.write(stability, source)
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Maturity.new(stability: stability, today: TODAY).verify!
      end
      assert_includes error.message, "maturity summary drift"
    end
  end

  private

  def document
    YAML.safe_load_file(REGISTRY, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def feature(value, id)
    value.fetch("features").find { |record| record.fetch("id") == id }
  end

  def assert_error(value, message)
    Dir.mktmpdir("maturity-registry-test-") do |directory|
      registry = File.join(directory, "maturity.yml")
      File.write(registry, YAML.dump(value))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Maturity.new(registry: registry, today: TODAY).verify!
      end
      assert_includes error.message, message
    end
  end
end
