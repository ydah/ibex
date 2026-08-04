# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/workloads"
require "tmpdir"
require "yaml"

# rubocop:disable Metrics/ClassLength -- one adversarial suite mutates every closed registry field family.
class WorkloadsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "docs/workloads.yml")
  DOCUMENTATION = File.join(ROOT, "docs/workloads.md")
  EVIDENCE = File.join(ROOT, "tool/quality/workloads/evidence.yml")

  def test_repository_registry_and_cross_manifest_bindings_are_valid
    assert Ibex::Quality::Workloads.new.verify!
  end

  def test_rejects_duplicate_and_noncanonical_workload_ids
    changed = document
    changed.fetch("workloads")[1]["id"] = changed.fetch("workloads").first.fetch("id")
    assert_error(changed, "unique canonical order")

    changed = document
    changed.fetch("workloads").first["id"] = "BCDice_parser"
    assert_error(changed, "canonical kebab-case id")
  end

  def test_rejects_mutable_short_and_mismatched_source_identities
    changed = document
    changed.fetch("workloads").first["revision"] = "main"
    assert_error(changed, "immutable full SHA-1")

    changed = document
    changed.fetch("workloads").first["revision"] = "21b4a037"
    assert_error(changed, "immutable full SHA-1")

    changed = document
    workload = changed.fetch("workloads").first
    workload.fetch("grammar")["source_url"] =
      workload.dig("grammar", "source_url").sub(workload.fetch("revision"), "main")
    assert_error(changed, "canonical primary URL")

    changed = document
    find_workload(changed, "gallery-calc")["revision"] = "a" * 40
    assert_error(changed, "absent at pinned revision")
  end

  def test_rejects_owner_and_source_classification_drift
    changed = document
    changed.fetch("workloads").first["owner"] = "another-owner"
    assert_error(changed, "owner/project do not match repository_url")

    changed = document
    find_workload(changed, "gallery-calc")["classification"] = "public_real"
    assert_error(changed, "classification does not match its source binding")
  end

  def test_rejects_path_escape_missing_file_and_local_digest_drift
    changed = document
    gallery = find_workload(changed, "gallery-calc")
    gallery.fetch("grammar")["path"] = "../grammar.y"
    assert_error(changed, "normalized relative path")

    changed = document
    gallery = find_workload(changed, "gallery-calc")
    gallery.fetch("grammar")["path"] = "gallery/calc/missing.y"
    assert_error(changed, "path is missing")

    changed = document
    find_workload(changed, "gallery-calc").fetch("grammar")["sha256"] = "0" * 64
    assert_error(changed, "digest drift")
  end

  def test_rejects_incomplete_fields_and_invented_measurement_states
    changed = document
    changed.fetch("workloads").first.delete("owner")
    assert_error(changed, "workload keys")

    changed = document
    find_workload(changed, "gallery-calc").dig("counts", "states").delete("value")
    assert_error(changed, "states keys")

    changed = document
    measurement = find_workload(changed, "bison-ruby-current-lrama").dig("counts", "productions")
    measurement["value"] = 695
    assert_error(changed, "productions keys")
  end

  def test_rejects_benchmark_eligibility_without_count_license_or_permission_evidence
    changed = document
    current_ruby = find_workload(changed, "bison-ruby-current-lrama")
    current_ruby.fetch("benchmark_eligibility")["status"] = "diagnostic_only"
    current_ruby.fetch("benchmark_eligibility")["scopes"] = ["partial_analysis"]
    assert_error(changed, "requires measured production, state, and token counts")

    changed = document
    find_workload(changed, "gallery-calc").dig("license", "evidence").clear
    assert_error(changed, "license evidence must be a non-empty array")

    changed = document
    find_workload(changed, "gallery-calc").dig("permission", "evidence").clear
    assert_error(changed, "permission evidence must be a non-empty array")
  end

  def test_rejects_public_and_bison_manifest_drift
    changed = document
    public_workload = changed.fetch("workloads").first
    old_revision = public_workload.fetch("revision")
    new_revision = "a" * 40
    public_workload["revision"] = new_revision
    replace_strings!(public_workload, old_revision, new_revision)
    assert_error(changed, "public workload manifest drift")

    changed = document
    find_workload(changed, "bison-gnu-calc").fetch("grammar")["sha256"] = "a" * 64
    assert_error(changed, "Bison external identity drift")
  end

  def test_every_public_metric_and_conflict_is_bound_to_the_fixed_manifest
    %w[productions states tokens].each do |metric|
      changed = document
      find_workload(changed, "bcdice-command-parser").dig("counts", metric)["value"] = 999
      assert_error(changed, "public workload metrics drift")
    end

    %w[reduce_reduce shift_reduce].each do |metric|
      changed = document
      find_workload(changed, "bcdice-command-parser").dig("known_conflicts", metric)["value"] = 999
      assert_error(changed, "public workload metrics drift")
    end
  end

  def test_every_bison_metric_and_conflict_including_tokens_is_bound_to_fixed_expected_values
    %w[productions states tokens].each do |metric|
      changed = document
      find_workload(changed, "bison-gnu-calc").dig("counts", metric)["value"] = 999
      assert_error(changed, "Bison external counts drift")
    end

    %w[reduce_reduce shift_reduce].each do |metric|
      changed = document
      find_workload(changed, "bison-gnu-calc").dig("known_conflicts", metric)["value"] = 999
      assert_error(changed, "Bison external counts drift")
    end
  end

  def test_remote_classification_requires_public_remote_primary_evidence
    changed = document
    workload = find_workload(changed, "bcdice-command-parser")
    workload.fetch("permission")["status"] = "repository_owned"
    assert_error(changed, "permission status conflicts with classification")

    changed = document
    workload = find_workload(changed, "bcdice-command-parser")
    workload.dig("license", "evidence", 0)["storage"] = "repository"
    assert_error(changed, "normalized relative path")

    changed = document
    workload = find_workload(changed, "bcdice-command-parser")
    workload["grammar"]["storage"] = "repository"
    assert_error(changed, "repository grammar source_url must be repository")

    changed = document
    find_workload(changed, "gallery-calc").fetch("permission")["status"] = "public_source"
    assert_error(changed, "permission status conflicts with classification")
  end

  def test_reviewed_remote_license_values_are_exact
    changed = document
    find_workload(changed, "bcdice-command-parser").fetch("license")["expression"] = "Apache-2.0"
    assert_error(changed, "differs from the reviewed fixture")

    changed = document
    license = find_workload(changed, "bcdice-command-parser").dig("license", "evidence", 0)
    license["locator"] = "https://evil.example/21b4a03789bf2080ad41aaf31299b609ee7bda86/LICENSE"
    assert_error(changed, "not a canonical primary GitHub URL")

    changed = document
    find_workload(changed, "bcdice-command-parser").dig("license", "evidence", 0)["sha256"] = "0" * 64
    assert_error(changed, "differs from the reviewed fixture")

    changed = document
    license = find_workload(changed, "bcdice-command-parser").dig("license", "evidence", 0)
    license["locator"] = license.fetch("locator").sub("/LICENSE", "/LICENSE.txt")
    assert_error(changed, "differs from the reviewed fixture")
  end

  def test_reviewed_remote_permission_values_are_exact
    changed = document
    permission = find_workload(changed, "bcdice-command-parser").dig("permission", "evidence", 0)
    permission["sha256"] = "0" * 64
    assert_error(changed, "differs from the reviewed fixture")

    changed = document
    permission = find_workload(changed, "bcdice-command-parser").dig("permission", "evidence", 0)
    permission["locator"] = permission.fetch("locator").sub("/parser.y", "/other.y")
    assert_error(changed, "differs from the reviewed fixture")
  end

  def test_reviewed_evidence_fixture_rejects_owner_path_revision_and_digest_mutations
    changed = evidence_document
    changed.fetch("records").first["owner"] = "other"
    assert_evidence_error(changed, "repository identity mismatch")

    changed = evidence_document
    changed.fetch("records").first["grammar"]["path"] = "lib/other.y"
    assert_evidence_error(changed, "fixed grammar source URL mismatch")

    changed = evidence_document
    changed.fetch("records").first["revision"] = "a" * 40
    assert_evidence_error(changed, "fixed grammar source URL mismatch")

    changed = evidence_document
    changed.fetch("records").first.dig("license", "evidence", 0)["sha256"] = "0" * 64
    assert_evidence_error(changed, "differs from the reviewed fixture")
  end

  def test_structurally_incomplete_import_cannot_publish_partial_counts_as_complete
    changed = document
    workload = find_workload(changed, "bison-ruby-current-lrama")
    workload["counts"] = {
      "method" => "ibex-normalized-lalr-v1",
      "productions" => { "status" => "measured", "value" => 695 },
      "states" => { "status" => "measured", "value" => 1152 },
      "tokens" => { "status" => "measured", "value" => 171 }
    }
    workload["known_conflicts"] = {
      "reduce_reduce" => { "status" => "measured", "value" => 0 },
      "shift_reduce" => { "status" => "measured", "value" => 27 }
    }
    workload["benchmark_eligibility"] = {
      "status" => "diagnostic_only",
      "scopes" => ["partial_analysis"],
      "reasons" => ["Mutation fixture must be rejected before publication."]
    }

    assert_error(changed, "structurally incomplete imports cannot publish complete counts")
  end

  def test_documentation_must_bind_every_stable_workload_and_problem_id
    source = File.read(DOCUMENTATION, encoding: Encoding::UTF_8).sub("`gallery-calc`", "gallery-calc")
    Dir.mktmpdir("workload-documentation-test-") do |directory|
      path = File.join(directory, "workloads.md")
      File.write(path, source)
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Workloads.new(documentation: path).verify!
      end
      assert_includes error.message, "missing stable id gallery-calc"
    end
  end

  private

  def document
    YAML.safe_load_file(REGISTRY, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def evidence_document
    YAML.safe_load_file(EVIDENCE, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def find_workload(value, id)
    value.fetch("workloads").find { |workload| workload.fetch("id") == id }
  end

  def assert_error(value, message)
    Dir.mktmpdir("workload-registry-test-") do |directory|
      path = File.join(directory, "workloads.yml")
      File.write(path, YAML.dump(value))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Workloads.new(registry: path).verify!
      end
      assert_includes error.message, message
    end
  end

  def assert_evidence_error(value, message)
    Dir.mktmpdir("workload-evidence-test-") do |directory|
      path = File.join(directory, "evidence.yml")
      File.write(path, YAML.dump(value))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Workloads.new(evidence: path).verify!
      end
      assert_includes error.message, message
    end
  end

  def replace_strings!(value, before, after)
    case value
    when Hash
      value.each_value { |entry| replace_strings!(entry, before, after) }
    when Array
      value.each { |entry| replace_strings!(entry, before, after) }
    when String
      value.replace(value.gsub(before, after))
    end
  end
end
# rubocop:enable Metrics/ClassLength
