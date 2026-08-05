# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"

class LexerProfileSchemaTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA = JSONSchemer.schema(JSON.parse(File.binread(File.join(ROOT, "schema/lexer-profile-v1.schema.json"))))
  EVIDENCE = File.join(ROOT, "tool/profile/evidence/lexer-profile-v1.json")

  def test_committed_evidence_has_a_closed_valid_shape
    assert_empty SCHEMA.validate(evidence).to_a

    changed = evidence
    changed["undeclared"] = true
    refute_empty SCHEMA.validate(changed).to_a
  end

  def test_timing_and_allocations_cannot_become_release_gates
    %w[elapsed_seconds allocated_objects].each do |field|
      changed = evidence
      measured(changed).dig("result", "runtime_observations", field)["release_gate"] = true
      refute_empty SCHEMA.validate(changed).to_a
    end
  end

  def test_source_classes_cannot_claim_the_other_cohorts_measurements
    changed = evidence
    measured(changed)["classification"] = "public_real"
    refute_empty SCHEMA.validate(changed).to_a

    changed = evidence
    public_workload = changed.fetch("cohorts").fetch(1).fetch("workloads").first
    public_workload["result"] = measured(changed).fetch("result")
    refute_empty SCHEMA.validate(changed).to_a
  end

  def test_decisions_are_fixed_to_the_reviewed_scopes
    changed = evidence
    changed.fetch("decisions").fetch(0)["decision"] = "GO"
    refute_empty SCHEMA.validate(changed).to_a

    changed = evidence
    changed.fetch("decisions").fetch(1)["feature"] = "regexp-backend-replacement"
    refute_empty SCHEMA.validate(changed).to_a
  end

  private

  def evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def measured(document)
    document.fetch("cohorts").fetch(0).fetch("workloads").first
  end
end
