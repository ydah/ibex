# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"

class ConstructionProfileSchemaTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA = JSONSchemer.schema(JSON.parse(File.binread(File.join(ROOT, "schema/construction-profile-v1.schema.json"))))
  EVIDENCE = File.join(ROOT, "tool/profile/evidence/construction-profile-v1.json")

  def test_rejects_source_class_and_availability_cross_contamination
    changed = evidence
    synthetic(changed).fetch("availability")["status"] = "verified_public_checkout"
    assert_rejected(changed)

    changed = evidence
    repository_real = changed.fetch("cohorts").last.fetch("workloads").find do |workload|
      workload.fetch("classification") == "repository_real"
    end
    repository_real["classification"] = "public_real"
    assert_rejected(changed)
  end

  def test_rejects_status_and_exhaustion_contradictions
    changed = evidence
    completed = completed_run(changed)
    completed["exhaustion"] = { "status" => "observed", "resource" => "wall_time", "limit" => 1.0 }
    assert_rejected(changed)

    changed = evidence
    run = completed_run(changed)
    make_failed(run, status: "limit_exceeded", resource: "wall_time", observed: false, limit: nil)
    assert_rejected(changed)
  end

  def test_rejects_algorithmically_false_not_applicable_metrics
    changed = evidence
    direct = completed_run(changed, "lalr")
    direct.fetch("structural")["propagation_edges"] = not_applicable
    assert_rejected(changed)

    changed = evidence
    ielr = completed_run(changed, "ielr")
    ielr.fetch("structural")["canonical_states"] = not_measured
    assert_rejected(changed)
  end

  def test_failed_metrics_must_be_not_measured
    changed = evidence
    run = completed_run(changed)
    make_failed(run, status: "failed", resource: "construction", observed: false, limit: nil)
    run.fetch("structural")["lr0_states"] = not_applicable

    assert_rejected(changed)
  end

  private

  def evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def synthetic(document)
    document.fetch("cohorts").first.fetch("workloads").first
  end

  def completed_run(document, algorithm = nil)
    workloads = document.fetch("cohorts").flat_map { |cohort| cohort.fetch("workloads") }
    runs = workloads.flat_map { |workload| workload.fetch("runs") }
                    .select { |run| run.fetch("status") == "completed" }
    algorithm ? runs.find { |run| run.fetch("algorithm") == algorithm } : runs.first
  end

  def make_failed(run, status:, resource:, observed:, limit:)
    run["status"] = status
    run["strategy"] = nil
    run["conflicts"] = nil
    run["structural"].transform_values! { not_measured }
    run["exhaustion"] = { "status" => observed ? "observed" : "not_observed", "resource" => resource,
                          "limit" => limit }
    run["failure"] = { "resource" => resource, "message" => "adversarial fixture" }
  end

  def not_applicable
    { "status" => "not_applicable", "reason" => "adversarial fixture" }
  end

  def not_measured
    { "status" => "not_measured", "reason" => "adversarial fixture" }
  end

  def assert_rejected(document)
    refute_empty SCHEMA.validate(document).to_a
  end
end
