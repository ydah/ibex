# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"
require "tmpdir"
require_relative "../../tool/quality/lexer_profile"

class QualityLexerProfileTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EVIDENCE = File.join(ROOT, "tool/profile/evidence/lexer-profile-v1.json")

  def test_committed_profile_matches_current_semantic_observations
    output = StringIO.new
    assert Ibex::Quality::LexerProfile.new(root: ROOT, output: output).verify!
    assert_match(/deterministic semantic observations/, output.string)
  end

  def test_runtime_observations_are_not_goldens
    changed = evidence
    observations = synthetic(changed).dig("result", "runtime_observations")
    observations.fetch("elapsed_seconds")["value"] = 99_999.0
    observations.fetch("allocated_objects")["value"] = 99_999

    assert verify(changed)
  end

  def test_tokenization_drift_is_rejected
    changed = evidence
    alternation = workload(changed, "adversarial-alternation")
    alternation.dig("result", "token_lengths", "sample", 0)["bytes"] = 2

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/token length|leftmost-first/, error.message)
  end

  def test_chunk_boundary_claim_requires_a_token_crossing_the_boundary
    changed = evidence
    chunk = workload(changed, "adversarial-chunk-boundary")
    chunk.dig("result", "streaming")["peak_buffer_bytes"] = 16_384

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/streaming boundary/, error.message)
  end

  def test_fabricated_provenance_is_rejected
    changed = evidence
    changed.fetch("provenance")["implementation_sha256"] = "0" * 64

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/implementation digest drift/, error.message)
  end

  def test_heuristic_policy_cannot_gain_false_authority
    changed = evidence
    changed.fetch("heuristic_analysis")["false_negative_possible"] = false

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/violates schema|heuristic analysis digest drift/, error.message)
  end

  private

  def evidence
    JSON.parse(File.binread(EVIDENCE))
  end

  def synthetic(document)
    document.fetch("cohorts").fetch(0).fetch("workloads").first
  end

  def workload(document, identifier)
    document.fetch("cohorts").fetch(0).fetch("workloads").find do |item|
      item.fetch("id") == identifier
    end
  end

  def verify(document)
    Dir.mktmpdir("ibex-lexer-profile") do |directory|
      path = File.join(directory, "evidence.json")
      File.binwrite(path, "#{JSON.pretty_generate(document)}\n")
      Ibex::Quality::LexerProfile.new(root: ROOT, evidence: path, output: StringIO.new).verify!
    end
  end
end
