# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "json_schemer"

class DirectMultiEntryDecisionTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EVIDENCE = File.join(ROOT, "tool/profile/evidence/construction-profile-v1.json")
  SCHEMA = File.join(ROOT, "schema/construction-profile-v1.schema.json")
  DOCUMENT = File.join(ROOT, "docs/direct-multi-entry-decision.md")

  def test_h005_machine_decision_classifies_m001_as_more_data
    assert_empty schemer.validate(evidence).to_a

    decision = multi_entry_decision
    assert_equal "MORE DATA", decision.fetch("decision")
    assert_equal(
      {
        "representative-real-multi-entry" => ["at least 2", "0", false],
        "synthetic-shared-isolated-coverage" => ["at least 1", "1", true],
        "practical-current-cost" =>
          ["state/item exhaustion or >=2x structural overhead on real inputs",
           "not observed on a real multi-entry workload", false]
      },
      decision.fetch("thresholds").to_h do |threshold|
        [threshold.fetch("id"), threshold.values_at("target", "observed", "satisfied")]
      end
    )
    assert_empty(real_workloads.select { |workload| workload.dig("entries", "count").to_i > 1 })
  end

  def test_synthetic_matrix_is_diagnostic_coverage_not_a_decision_gate
    matrix = synthetic_workloads.find { |workload| workload.fetch("id") == "matrix-multi-entry" }
    assert_equal "repository_synthetic", matrix.fetch("classification")
    assert_equal({ "count" => 2, "names" => %w[document atom] }, matrix.fetch("entries"))

    expected_runs = [%w[lalr shared], %w[ielr shared], %w[lalr isolated], %w[ielr isolated]]
    actual_runs = matrix.fetch("runs").map { |run| run.values_at("algorithm", "entry_mode") }
    assert_equal expected_runs, actual_runs
    matrix.fetch("runs").each do |run|
      assert_equal "completed", run.fetch("status")
      metrics = %w[final_states final_items final_lookahead_items].map do |field|
        run.dig("structural", field, "value")
      end
      assert_equal [9, 14, 20], metrics
      assert_equal({ "shift_reduce" => 0, "reduce_reduce" => 0 }, run.fetch("conflicts"))
      refute run.dig("observations", "elapsed_seconds", "release_gate")
    end
    assert_equal "MORE DATA", multi_entry_decision.fetch("decision")
  end

  def test_reconsideration_and_follow_on_boundaries_are_explicit
    assert_equal(
      [
        "verified real multi-entry grammars show material shared construction cost",
        "a direct construction preserves shared-entry conflict attribution",
        "an owner accepts the semantic and maintenance plan"
      ],
      multi_entry_decision.fetch("counterevidence_required")
    )

    document = File.binread(DOCUMENT)
    assert_includes document, "M001 is **MORE DATA**"
    assert_includes document, "H005 records zero real multi-entry workloads"
    assert_includes document, "All four M001 conditions require real-workload evidence"
    assert_includes document, "it is a `repository_synthetic` workload"
    assert_includes document, "M001 is independent of the direct IELR decision"
    assert_includes document, "no I002-I006-equivalent adequacy specification"
  end

  def test_public_index_and_package_include_the_decision_document
    readme = File.binread(File.join(ROOT, "README.md"))
    specification = Gem::Specification.load(File.join(ROOT, "ibex.gemspec"))

    assert_includes readme, "docs/direct-multi-entry-decision.md"
    assert_includes specification.files, "docs/direct-multi-entry-decision.md"
    assert_includes specification.files, "schema/construction-profile-v1.schema.json"
  end

  private

  def evidence
    @evidence ||= JSON.parse(File.binread(EVIDENCE))
  end

  def schemer
    @schemer ||= JSONSchemer.schema(JSON.parse(File.binread(SCHEMA)))
  end

  def multi_entry_decision
    evidence.fetch("decisions").find { |decision| decision.fetch("feature") == "direct-multi-entry" }
  end

  def real_workloads
    evidence.fetch("cohorts").find { |cohort| cohort.fetch("kind") == "real" }.fetch("workloads")
  end

  def synthetic_workloads
    evidence.fetch("cohorts").find { |cohort| cohort.fetch("kind") == "synthetic" }.fetch("workloads")
  end
end
