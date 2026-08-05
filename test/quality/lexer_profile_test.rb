# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
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

  def test_base_revision_cannot_be_rewritten_to_an_ancestor
    changed = evidence
    provenance = changed.fetch("provenance")
    ancestor = git!("rev-parse", "#{provenance.fetch('base_revision')}^1").strip
    provenance["base_revision"] = ancestor
    provenance.fetch("bound_paths").each do |binding|
      bytes = git_object(ancestor, binding.fetch("path"))
      base_sha = Digest::SHA256.hexdigest(bytes) if bytes
      binding["base_sha256"] = base_sha
      binding["git_state"] =
        if base_sha.nil?
          "untracked"
        elsif base_sha == binding.fetch("sha256")
          "base"
        else
          "modified"
        end
    end
    resign_capture!(provenance, status_for(provenance.fetch("bound_paths")))

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/capture identity is not bound by committed evidence history/, error.message)
  end

  def test_capture_clean_status_cannot_be_rewritten
    changed = evidence
    provenance = changed.fetch("provenance")
    resign_capture!(provenance, [" M README.md"])

    error = assert_raises(RuntimeError) { verify(changed) }
    assert_match(/capture identity is not bound by committed evidence history/, error.message)
  end

  def test_depth_one_checkout_fails_closed_without_capture_parent
    Dir.mktmpdir("ibex-lexer-profile-shallow") do |directory|
      checkout = File.join(directory, "checkout")
      assert system("git", "clone", "--quiet", "--depth=1", "file://#{ROOT}", checkout)

      error = assert_raises(RuntimeError) do
        Ibex::Quality::LexerProfile.new(root: checkout, output: StringIO.new).verify!
      end
      assert_match(/capture history is unavailable/, error.message)
    end
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

  def resign_capture!(provenance, status)
    provenance["capture_worktree_clean"] = status.empty?
    provenance["capture_worktree_status"] = status
    provenance["capture_worktree_status_sha256"] = Ibex::Profile::LexerProfileDigest.sha256(status)
    provenance["bound_paths_sha256"] = Ibex::Profile::LexerProfileDigest.sha256(provenance.fetch("bound_paths"))
    provenance["capture_identity_sha256"] = Ibex::Profile::LexerProfileProvenance.capture_identity(provenance)
  end

  def status_for(bindings)
    bindings.filter_map do |binding|
      case binding.fetch("git_state")
      when "modified" then " M #{binding.fetch('path')}"
      when "untracked" then "?? #{binding.fetch('path')}"
      end
    end
  end

  def git_object(revision, path)
    output, _error, status = Open3.capture3("git", "show", "#{revision}:#{path}", chdir: ROOT)
    output.b if status.success?
  end

  def git!(*arguments)
    output, error, status = Open3.capture3("git", *arguments, chdir: ROOT)
    raise "git #{arguments.join(' ')} failed: #{error}" unless status.success?

    output
  end

  def verify(document)
    Dir.mktmpdir("ibex-lexer-profile") do |directory|
      path = File.join(directory, "evidence.json")
      File.binwrite(path, "#{JSON.pretty_generate(document)}\n")
      Ibex::Quality::LexerProfile.new(root: ROOT, evidence: path, output: StringIO.new).verify!
    end
  end
end
