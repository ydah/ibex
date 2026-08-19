# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "json"
require "json_schemer"
require "open3"
require "stringio"
require "tmpdir"
require_relative "../../tool/quality/direct_ielr_decision"

class DirectIELRDecisionTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DOSSIER = File.join(ROOT, "tool/quality/evidence/direct-ielr-decision-v1.json")
  SCHEMA = File.join(ROOT, "schema/direct-ielr-decision-v1.schema.json")
  SHALLOW_BOUNDARY_BASE = "ceab7bf5dfedff5f9ecf6afed376fbdb95c6d0a3"
  V001_REVISION = "f9d2c54eb4b27fc5ffe798bb0b29d038d97ee35c"

  def test_committed_no_go_matches_h005_and_v001
    output = StringIO.new
    result = Ibex::Quality::DirectIELRDecision.new(root: ROOT, output: output).verify!

    assert_equal "NO-GO", result.dig("decision", "value")
    assert_match(/matches H005 and V001 evidence/, output.string)
  end

  def test_schema_is_a_closed_json_schema_2020_12_document
    schema = JSON.parse(File.binread(SCHEMA))

    assert_equal "https://json-schema.org/draft/2020-12/schema", schema.fetch("$schema")
    assert_equal false, schema.fetch("additionalProperties")
    assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
    assert_empty JSONSchemer.schema(schema).validate(dossier).to_a
  end

  def test_go_condition_or_i002_promotion_is_rejected
    changed = dossier
    changed.dig("policy", "go_conditions", 0)["status"] = "satisfied"
    assert_verification_error(changed, /GO condition inventory drift/)

    changed = dossier
    changed.fetch("follow_on")["i002_authorized"] = true
    assert_verification_error(changed, /violates schema|I002 must remain blocked/)
  end

  def test_scale_cost_and_verification_gaps_cannot_gain_false_assurance
    changed = dossier
    changed.dig("observations", "canonical_scale_cost")["status"] = "resolved"
    assert_verification_error(changed, /violates schema|must remain unresolved/)

    changed = dossier
    changed.fetch("verification_gaps")["split_witnesses"] = "verified"
    assert_verification_error(changed, /violates schema|unsupported IELR verification/)
  end

  def test_workload_counts_and_evidence_digests_are_bound
    changed = dossier
    changed.fetch("observations")["real_ielr_required_workloads"] = 1
    assert_verification_error(changed, /violates schema|unsubstantiated real IELR need/)

    changed = dossier
    changed.dig("evidence_identity", "sources", 0)["sha256"] = "0" * 64
    assert_verification_error(changed, /evidence source digest drift/)
  end

  def test_evidence_source_paths_and_roles_are_closed
    changed = dossier
    revision = changed.dig("decision", "revision")
    bytes = git!(ROOT, "show", "#{revision}:Gemfile")
    digest = Digest::SHA256.hexdigest(bytes.b)
    changed.dig("evidence_identity", "sources").each do |source|
      source["id"] = "substituted-source"
      source["path"] = "Gemfile"
      source["sha256"] = digest
      source["role"] = "substituted source"
    end
    sources = changed.dig("evidence_identity", "sources")
    changed["evidence_identity"]["sources_sha256"] = Digest::SHA256.hexdigest(JSON.generate(sources))

    assert_verification_error(changed, /evidence source inventory drift/)
  end

  def test_decision_and_v001_revisions_and_role_are_exact
    changed = dossier
    changed.fetch("decision")["revision"] = "f237eb9274ef7b6ed1bd63fc6fb1a6b1d899989f"
    assert_verification_error(changed, /decision revision identity drift/)

    changed = dossier
    changed.fetch("evidence_identity")["v001_revision"] =
      git!(ROOT, "rev-list", "--max-parents=0", "HEAD").strip
    assert_verification_error(changed, /V001 revision identity drift/)

    changed = dossier
    changed.fetch("decision")["revision_role"] = "dossier publication revision"
    assert_verification_error(changed, /violates schema|decision revision role drift/)

    changed = dossier
    changed.fetch("decision")["date"] = "2099-01-01"
    assert_verification_error(changed, /decision date identity drift/)
  end

  def test_condition_observations_and_reconsideration_evidence_are_closed
    changed = dossier
    changed.dig("policy", "go_conditions", 0)["observed"] = "none"
    result, = Ibex::Quality::DirectIELRDecision.new(root: ROOT, output: StringIO.new).verify_semantics!(changed)
    assert_equal "NO-GO", result.dig("decision", "value")

    changed = dossier
    changed.dig("policy", "no_go_conditions", 0)["observed"] = "condition is not satisfied"
    result, = Ibex::Quality::DirectIELRDecision.new(root: ROOT, output: StringIO.new).verify_semantics!(changed)
    assert_equal "NO-GO", result.dig("decision", "value")

    changed = dossier
    changed.dig("reconsideration_triggers", 0)["id"] = "unknown-trigger"
    assert_verification_error(changed, /reconsideration trigger inventory drift/)
  end

  def test_gpl_implementation_lineage_is_rejected
    changed = dossier
    changed.fetch("legal_provenance")["gpl_implementation_source_used"] = true

    assert_verification_error(changed, /violates schema|legal provenance/)
  end

  def test_depth_one_checkout_after_dossier_commit_fails_closed
    Dir.mktmpdir("ibex-direct-ielr-shallow") do |directory|
      staging = File.join(directory, "staging")
      checkout = File.join(directory, "checkout")
      assert system("git", "clone", "--quiet", "--depth=1", "file://#{ROOT}", staging)
      copy_dossier_contract(staging)
      git!(staging, "add", "schema/direct-ielr-decision-v1.schema.json",
           "tool/quality/evidence/direct-ielr-decision-v1.json")
      git!(staging, "-c", "user.name=Ibex Test", "-c", "user.email=test@example.invalid",
           "commit", "--quiet", "--allow-empty", "-m", "test: advance after decision dossier")
      assert system("git", "clone", "--quiet", "--depth=1", "file://#{staging}", checkout)

      error = assert_raises(RuntimeError) do
        Ibex::Quality::DirectIELRDecision.new(root: checkout, output: StringIO.new).verify!
      end
      assert_match(/requires full Git history/, error.message)
    end
  end

  def test_shallow_v001_boundary_cannot_masquerade_as_source_introduction
    Dir.mktmpdir("ibex-direct-ielr-v001-boundary") do |directory|
      staging = File.join(directory, "staging")
      checkout = File.join(directory, "checkout")
      assert system("git", "clone", "--quiet", ROOT, staging)
      git!(staging, "switch", "--detach", SHALLOW_BOUNDARY_BASE)
      git!(staging, "-c", "user.name=Ibex Test", "-c", "user.email=test@example.invalid",
           "commit", "--quiet", "--allow-empty", "-m", "test: place V001 at shallow boundary")
      git!(staging, "branch", "-D", "main")
      git!(staging, "branch", "shallow-boundary", "HEAD")
      assert system("git", "clone", "--quiet", "--depth=64", "--single-branch", "--no-tags",
                    "--branch=shallow-boundary",
                    "file://#{staging}", checkout)
      assert git_success?(checkout, "cat-file", "-e", "#{V001_REVISION}^{commit}")
      refute git_success?(checkout, "cat-file", "-e", "#{V001_REVISION}^^{commit}")

      error = assert_raises(RuntimeError) do
        Ibex::Quality::DirectIELRDecision.new(root: checkout, output: StringIO.new).verify!
      end
      assert_match(/requires full Git history/, error.message)
    end
  end

  def test_public_document_is_indexed_and_points_to_machine_record
    readme = File.binread(File.join(ROOT, "README.md"))
    document = File.binread(File.join(ROOT, "docs/records/ielr/direct-ielr-decision.md"))

    assert_includes readme, "docs/records/ielr/direct-ielr-decision.md"
    assert_includes document, "direct-ielr-decision-v1.json"
    assert_includes document, "direct-ielr-decision-v1.schema.json"
    assert_includes document, "I002 remains\nblocked"
  end

  private

  def dossier
    JSON.parse(File.binread(DOSSIER))
  end

  def assert_verification_error(document, message)
    error = assert_raises(RuntimeError) { verify(document) }
    assert_match message, error.message
  end

  def verify(document)
    Dir.mktmpdir("ibex-direct-ielr-decision") do |directory|
      path = File.join(directory, "dossier.json")
      File.binwrite(path, "#{JSON.pretty_generate(document)}\n")
      Ibex::Quality::DirectIELRDecision.new(root: ROOT, dossier: path, output: StringIO.new).verify!
    end
  end

  def copy_dossier_contract(destination)
    [
      "schema/direct-ielr-decision-v1.schema.json",
      "tool/quality/evidence/direct-ielr-decision-v1.json"
    ].each do |relative|
      target = File.join(destination, relative)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(ROOT, relative), target)
    end
  end

  def git!(root, *arguments)
    output, error, status = Open3.capture3("git", *arguments, chdir: root)
    raise "git #{arguments.join(' ')} failed: #{error}" unless status.success?

    output
  end

  def git_success?(root, *arguments)
    _output, _error, status = Open3.capture3("git", *arguments, chdir: root)
    status.success?
  end
end
