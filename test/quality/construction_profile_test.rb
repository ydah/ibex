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

  def test_workload_and_run_entry_mismatch_is_rejected
    changed = evidence
    workload = measured_workload(changed)
    workload.fetch("runs").first["entries"] += 1

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/workload entries do not match construction run entries/, error.message)
  end

  def test_fabricated_host_observation_is_rejected
    %w[ruby_version kernel_release host_cpu rubyopt].each do |field|
      changed = evidence
      changed.fetch("environment")[field] = "fabricated"
      assert_provenance_error(changed, /environment observation digest drift/)
    end
  end

  def test_fabricated_source_and_capture_provenance_is_rejected
    changed = evidence
    changed.fetch("provenance")["base_revision"] = "0" * 40
    assert_provenance_error(changed, /base revision is unavailable/)

    changed = evidence
    changed.fetch("provenance")["capture_worktree_clean"] = true
    assert_provenance_error(changed, /capture clean-state drift/)

    changed = evidence
    changed.fetch("provenance")["implementation_sha256"] = "0" * 64
    assert_provenance_error(changed, /implementation digest drift/)

    changed = evidence
    changed.fetch("provenance").fetch("bound_paths").first["sha256"] = "0" * 64
    assert_provenance_error(changed, /bound source drift/)
  end

  def test_fabricated_measurement_options_are_rejected
    changed = evidence
    changed.fetch("measurement_policy")["wall_seconds_per_run"] = 1.0

    assert_provenance_error(changed, /measurement policy digest drift/)
  end

  private

  def evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def completed_run(document)
    workloads = document.fetch("cohorts").flat_map { |cohort| cohort.fetch("workloads") }
    workloads.flat_map { |workload| workload.fetch("runs") }
             .find { |run| run.fetch("status") == "completed" }
  end

  def measured_workload(document)
    workloads = document.fetch("cohorts").flat_map { |cohort| cohort.fetch("workloads") }
    workloads.find { |workload| !workload.fetch("runs").empty? }
  end

  def assert_provenance_error(document, message)
    error = assert_raises(RuntimeError) { verify(document) }
    assert_match message, error.message
  end

  def verify(document)
    Dir.mktmpdir("ibex-construction-profile") do |directory|
      path = File.join(directory, "evidence.json")
      File.binwrite(path, "#{JSON.pretty_generate(document)}\n")
      Ibex::Quality::ConstructionProfile.new(root: ROOT, evidence: path, output: StringIO.new).verify!
    end
  end
end
