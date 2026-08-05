# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"
require "tmpdir"
require_relative "../../tool/quality/construction_profile"

class QualityConstructionProfileTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EVIDENCE = File.join(ROOT, "tool/profile/evidence/construction-profile-v1.json")

  def test_committed_profile_matches_current_structural_observations
    output = StringIO.new
    assert Ibex::Quality::ConstructionProfile.new(root: ROOT, output: output).verify!
    assert_match(/deterministic structural observations/, output.string)
  end

  def test_structural_drift_is_rejected
    changed = evidence
    run = completed_run(changed)
    run.dig("structural", "final_states")["value"] += 1

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/structural evidence drift/, error.message)
  end

  def test_elapsed_observation_is_not_a_golden
    changed = evidence
    completed_run(changed).dig("observations", "elapsed_seconds")["value"] = 999.0

    assert verify(changed)
  end

  private

  def evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def completed_run(document)
    document.fetch("cohorts").flat_map { |cohort| cohort.fetch("workloads") }
                             .flat_map { |workload| workload.fetch("runs") }
                             .find { |run| run.fetch("status") == "completed" }
  end

  def verify(document)
    Dir.mktmpdir("ibex-construction-profile") do |directory|
      path = File.join(directory, "evidence.json")
      File.binwrite(path, "#{JSON.pretty_generate(document)}\n")
      Ibex::Quality::ConstructionProfile.new(root: ROOT, evidence: path, output: StringIO.new).verify!
    end
  end
end
