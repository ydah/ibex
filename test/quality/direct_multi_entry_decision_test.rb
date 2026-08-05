# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "json_schemer"
require_relative "../../tool/profile/construction_profiler"

class DirectMultiEntryDecisionTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EVIDENCE = File.join(ROOT, "tool/profile/evidence/construction-profile-v1.json")
  SCHEMA = File.join(ROOT, "schema/construction-profile-v1.schema.json")
  DOCUMENT = File.join(ROOT, "docs/direct-multi-entry-decision.md")

  def test_h005_machine_decision_classifies_m001_as_more_data
    refute_empty schemer.validate(evidence).to_a
    assert_empty schemer.validate(evidence_with_current_multi_entry_decision).to_a

    decision = current_multi_entry_decision
    assert_equal "MORE DATA", decision.fetch("decision")
    assert_equal(
      {
        "representative-real-multi-entry" =>
          ["at least 2 verified real grammars with multiple entries",
           "0 verified real multi-entry grammars", false],
        "material-canonical-fallback-cost" =>
          ["canonical fallback exhaustion or >=2x structural overhead on verified real inputs",
           "not observed on a real multi-entry workload", false],
        "clear-shared-benefit-over-isolation" =>
          ["shared construction materially improves over isolation on verified real inputs",
           "not observed on a real multi-entry workload", false],
        "conflict-attribution-preservation" =>
          ["adversarial conflicting fixtures preserve per-entry attribution against an independent semantic oracle",
           "not established: the synthetic matrix has no conflicts and no direct mechanism", false]
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

    lalr_runs = matrix.fetch("runs").select { |run| run.fetch("algorithm") == "lalr" }
    shared = lalr_runs.find { |run| run.fetch("entry_mode") == "shared" }
    isolated = lalr_runs.find { |run| run.fetch("entry_mode") == "isolated" }
    refute_nil shared
    refute_nil isolated

    lalr_runs.each { |run| assert_diagnostic_run(run) }
    assert_equal lalr_structure(isolated), lalr_structure(shared)

    decision = current_multi_entry_decision
    assert_equal "MORE DATA", decision.fetch("decision")
    refute threshold(decision, "conflict-attribution-preservation").fetch("satisfied")
  end

  def test_reconsideration_and_follow_on_boundaries_are_explicit
    assert_equal(
      [
        "at least two verified real grammars with multiple entries",
        "verified real multi-entry grammars show material canonical fallback cost",
        "shared construction shows a clear structural benefit over isolation on those real grammars",
        "adversarial conflicting fixtures preserve per-entry attribution against an independent semantic oracle",
        "an owner accepts the semantic and maintenance plan"
      ],
      current_multi_entry_decision.fetch("counterevidence_required")
    )

    document = File.binread(DOCUMENT)
    assert_includes document, "M001 is **MORE DATA**"
    assert_includes document, "H005 records zero real multi-entry workloads"
    assert_includes document, "The first three M001 conditions require verified real-workload evidence"
    assert_match(/adversarial\s+synthetic conflicting fixtures checked by an independent semantic oracle/, document)
    assert_includes document, "bounded design proof or\nreachability analysis"
    assert_includes document, "fresh H005 capture at a fresh exact revision"
    assert_includes document, "production direct\nconstructor, public experiment"
    assert_includes document, "it is a `repository_synthetic` workload"
    assert_includes document, "M001 is independent of the direct IELR decision"
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

  def current_multi_entry_decision
    @current_multi_entry_decision ||=
      Ibex::Profile::ConstructionDecisions.new(evidence.fetch("cohorts")).build.find do |decision|
        decision.fetch("feature") == "direct-multi-entry"
      end
  end

  def evidence_with_current_multi_entry_decision
    document = JSON.parse(JSON.generate(evidence))
    index = document.fetch("decisions").index { |decision| decision.fetch("feature") == "direct-multi-entry" }
    document.fetch("decisions")[index] = current_multi_entry_decision
    document
  end

  def threshold(decision, id)
    decision.fetch("thresholds").find { |item| item.fetch("id") == id }
  end

  def assert_diagnostic_run(run)
    assert_equal "completed", run.fetch("status")
    assert_equal({ "shift_reduce" => 0, "reduce_reduce" => 0 }, run.fetch("conflicts"))
    refute run.dig("observations", "elapsed_seconds", "release_gate")
  end

  def lalr_structure(run)
    %w[final_states final_items final_lookahead_items].to_h do |field|
      [field, run.dig("structural", field)]
    end
  end

  def real_workloads
    evidence.fetch("cohorts").find { |cohort| cohort.fetch("kind") == "real" }.fetch("workloads")
  end

  def synthetic_workloads
    evidence.fetch("cohorts").find { |cohort| cohort.fetch("kind") == "synthetic" }.fetch("workloads")
  end
end
