# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/maturity"
require "date"
require "fileutils"
require "tmpdir"
require "yaml"

# rubocop:disable Metrics/ClassLength -- one adversarial suite mutates every closed evidence family.
class MaturityTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "docs/registry/maturity.yml")
  NARRATIVE = File.join(ROOT, "docs/policy/maturity.md")
  TODAY = Date.new(2026, 8, 15)
  KNOWN_NONSEMANTIC_MAPPINGS = {
    "semantic-locations-types" => {
      "v0.2.0..reviewed" => %w[
        021994f6342c2795d19ee90e58fbf7386ef5fa95
        1e332a694abbc0b520af97d8a205dc8b8d311360
        643365686f7a04578b5794a73b8e64028e497f7e
      ]
    },
    "action-shadow" => {
      "introduction..v0.2.0" => %w[f7e1533003989b4c13f6158f4c482ba5cc3b9090]
    },
    "incremental-cst" => {
      "v0.2.0..reviewed" => %w[
        021994f6342c2795d19ee90e58fbf7386ef5fa95
        1e332a694abbc0b520af97d8a205dc8b8d311360
        643365686f7a04578b5794a73b8e64028e497f7e
      ]
    }
  }.freeze

  def test_repository_inventory_evidence_and_public_summaries_are_valid
    assert Ibex::Quality::Maturity.new(today: TODAY).verify!
  end

  def test_review_date_covers_the_reviewed_commit_in_its_recorded_timezone
    revision = document.dig("audit", "reviewed_repository_revision")

    assert_equal Date.new(2026, 8, 15), Ibex::Quality::Maturity.commit_date(ROOT, revision)

    changed = document
    changed.fetch("audit")["reviewed_at"] = "2026-08-04"
    assert_error(changed, "reviewed commit timestamp cannot be after maturity reviewed_at")
  end

  def test_rejects_a_missing_duplicate_or_reordered_feature
    changed = document
    changed.fetch("features").pop
    assert_error(changed, "exact 19 Preview + 2 Experimental")

    changed = document
    changed.fetch("features")[1]["id"] = changed.fetch("features").first.fetch("id")
    assert_error(changed, "unique identifiers")

    changed = document
    changed.fetch("features").rotate!
    assert_error(changed, "exact 19 Preview + 2 Experimental")
  end

  def test_rejects_silent_maturity_changes_and_promotion_without_release_evidence
    changed = document
    feature(changed, "ielr")["maturity"] = "stable"
    assert_error(changed, "silent promotion or removal")

    changed = document
    decision = feature(changed, "ielr").fetch("decision")
    decision["outcome"] = "promote"
    decision["target_maturity"] = "stable"
    assert_error(changed, "promotion requires met criteria")

    changed = document
    decision = feature(changed, "ielr").fetch("decision")
    decision["outcome"] = "promote"
    decision["target_maturity"] = "stable"
    decision["criteria_status"] = "met"
    assert_error(changed, "forbidden before R001 and exact-revision R002")
  end

  def test_rejects_synthetic_or_diagnostic_evidence_as_external_use
    changed = document
    use = feature(changed, "generated-lexers").fetch("external_use")
    use["status"] = "demonstrated"
    assert_error(changed, "cannot prove external use")

    changed = document
    use = feature(changed, "semantic-locations-types").fetch("external_use")
    use["status"] = "demonstrated"
    assert_error(changed, "cannot prove external use")

    changed = document
    use = feature(changed, "lsp").fetch("external_use")
    use["status"] = "demonstrated"
    assert_error(changed, "requires workload IDs")

    changed = document
    use = feature(changed, "lsp").fetch("external_use")
    use["status"] = "demonstrated"
    use["workload_ids"] = ["bcdice-command-parser"]
    assert_error(changed, "do not bind the claimed feature use")
  end

  def test_rejects_missing_documentation_tooling_limitations_and_review_triggers
    changed = document
    feature(changed, "lsp").dig("documentation", "evidence").clear
    assert_error(changed, "documentation evidence must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("documentation", "gaps").clear
    assert_error(changed, "documentation gaps must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("dependent_tooling", "evidence").clear
    assert_error(changed, "tooling evidence must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("dependent_tooling", "gaps").clear
    assert_error(changed, "tooling gaps must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("limitations", "performance").clear
    assert_error(changed, "performance limitations must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("limitations", "safety").clear
    assert_error(changed, "safety limitations must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("next_review", "triggers").clear
    assert_error(changed, "next review triggers must be a non-empty")
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- mutations cover every issue provenance field family.
  def test_rejects_stale_incomplete_or_unknown_issue_audits
    changed = document
    changed.dig("audit", "issue_audits", 0)["fresh_until"] = "2026-08-03"
    assert_error(changed, "checked_at must not follow fresh_until")

    changed = document
    audit = changed.dig("audit", "issue_audits", 0)
    audit["checked_at"] = "2026-08-16"
    audit["fresh_until"] = "2026-09-05"
    assert_error(changed, "checked_at cannot be in the future")

    changed = document
    audit = changed.dig("audit", "issue_audits", 0)
    audit["checked_at"] = "2026-08-16"
    audit["fresh_until"] = "2026-09-05"
    assert_error(changed, "checked_at cannot follow the maturity review", today: Date.new(2026, 8, 16))

    changed = document
    changed.dig("audit", "issue_audits", 0, "result")["status"] = "unknown"
    assert_error(changed, "result status must be complete")

    changed = document
    changed.dig("audit", "issue_audits", 0, "result")["incomplete_results"] = true
    assert_error(changed, "incomplete GitHub issue results")

    changed = document
    feature(changed, "debug")["issue_audit"]["status"] = "unknown"
    assert_error(changed, "must be none_found or open_found")

    changed = document
    changed.dig("audit", "issue_audits", 0, "result")["total_count"] = 1
    assert_error(changed, "count does not match issues")

    changed = document
    result = changed.dig("audit", "issue_audits", 0, "result")
    result["total_count"] = 1
    result["issues"] = [issue_record(feature_ids: ["lsp"])]
    assert_error(changed, "issue status must derive from machine issue dispositions")

    changed = document
    result = changed.dig("audit", "issue_audits", 0, "result")
    result["total_count"] = 1
    result["issues"] = [issue_record(feature_ids: [], rationale: "")]
    assert_error(changed, "not_applicable_rationale must be a non-empty")

    changed = document
    result = changed.dig("audit", "issue_audits", 0, "result")
    result["total_count"] = 1
    result["issues"] = [issue_record(feature_ids: [])]
    result.dig("issues", 0)["url"] = "https://example.test/issues/123"
    assert_error(changed, "issue URL must be canonical")

    changed = document
    result = changed.dig("audit", "issue_audits", 0, "result")
    result["total_count"] = 1
    result["issues"] = [issue_record(feature_ids: %w[lsp lsp])]
    assert_error(changed, "feature_ids must be unique canonical order")
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # rubocop:disable Metrics/AbcSize -- mutations cover every release-history boundary field family.
  def test_rejects_false_or_noncanonical_history
    changed = document
    feature(changed, "watch").dig("specification_history", "unknowns").clear
    assert_error(changed, "specification history unknowns must be a non-empty")

    changed = document
    feature(changed, "watch").dig("specification_history", "introduction")["revision"] =
      "dcdd015ae2a8ca48e9ab9c64af4baa6264c39705"
    assert_error(changed, "introduction authority drift")

    changed = document
    feature(changed, "watch").dig("specification_history", "introduction")["revision"] =
      "7025560263fedfd8724cf25387ede86cd981ca3f"
    assert_error(changed, "introduction is outside reviewed history")

    changed = document
    feature(changed, "watch").dig("specification_history", "first_release")["tag"] = "v0.1.0"
    assert_error(changed, "first release tag drift")

    changed = document
    feature(changed, "watch").dig("specification_history", "snapshots").rotate!
    assert_error(changed, "snapshots must cover v0.1.0, v0.2.0, and reviewed in order")

    changed = document
    feature(changed, "watch").dig("specification_history", "snapshots", 1)["source_tree_sha256"] = "0" * 64
    assert_error(changed, "snapshot source tree digest drift")

    changed = document
    feature(changed, "watch").dig("specification_history", "changes").reverse!
    assert_error(changed, "change boundaries must be chronological and canonical")

    changed = document
    changed.fetch("audit")["reviewed_repository_revision"] = "24c6712db0a3da8f42f13d32b43392ba261adfed"
    assert_error(changed, "exact reviewed revision authority")
  end
  # rubocop:enable Metrics/AbcSize

  def test_rejects_forged_introduction_and_canonical_presence
    changed = document
    introduction = feature(changed, "parameterized-rules").dig("specification_history", "introduction")
    introduction["path"] = "README.md"
    introduction["query"] = "Ibex"
    introduction["revision"] = "1bce63f7734a6df2bef3f9d7de87680093a8d2a2"
    assert_error(changed, "introduction authority drift")

    changed = document
    snapshot = feature(changed, "parameterized-rules").dig("specification_history", "snapshots", 0)
    snapshot["canonical_presence"]["status"] = "complete"
    assert_error(changed, "canonical presence status drift")
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- adversarial mutations cover the commit audit contract.
  def test_rejects_incomplete_unrelated_or_forged_commit_assessments
    changed = document
    audit = feature(changed, "ebnf-groups").dig("specification_history", "changes", 1)
    audit["classification"] = "semantic_change"
    assert_error(changed, "semantic history classification drift")

    changed = document
    audit = feature(changed, "parameterized-rules").dig("specification_history", "changes", 0)
    assessment = audit.fetch("commit_assessments").first
    assessment["classification"] = "internal_refactor"
    assessment["contract_effect"] =
      "#{assessment.fetch('summary')} changes lib/ibex/frontend/ast.rb implementation mechanics, " \
      "preserving the public contract for this row."
    assert_error(changed, "semantic commit authority drift")

    changed = document
    assessments = feature(changed, "parameterized-rules").dig(
      "specification_history", "changes", 0, "commit_assessments"
    )
    assessments.pop
    assert_error(changed, "commit assessment revision set or order drift")

    changed = document
    assessments = feature(changed, "parameterized-rules").dig(
      "specification_history", "changes", 0, "commit_assessments"
    )
    assessments << assessments.first.dup
    assert_error(changed, "commit assessments must have unique identifiers")

    changed = document
    assessment = feature(changed, "watch").dig(
      "specification_history", "changes", 0, "commit_assessments", 0
    )
    revision = "68f649ac42af45cdbe179f4afe080c8920f0ff9d"
    subject = Ibex::Quality::Maturity.commit_subject(ROOT, revision)
    assessment.replace(
      "revision" => revision,
      "classification" => "no_semantic_change",
      "summary" => subject,
      "contract_effect" =>
        "#{subject} changes an adjacent area; the watch public contract remains unchanged in this audit."
    )
    assert_error(changed, "commit assessment is unrelated to its audited paths")

    changed = document
    assessment = feature(changed, "watch").dig(
      "specification_history", "changes", 0, "commit_assessments", 0
    )
    assessment["summary"] = "Forged subject"
    assert_error(changed, "commit assessment subject drift")

    changed = document
    assessment = feature(changed, "watch").dig(
      "specification_history", "changes", 0, "commit_assessments", 0
    )
    assessment["contract_effect"] = "Generic rationale"
    assert_error(changed, "commit-specific rationale containing the exact subject")

    changed = document
    assessment = feature(changed, "watch").dig(
      "specification_history", "changes", 0, "commit_assessments", 0
    )
    assessment["revision"] = "7025560263fedfd8724cf25387ede86cd981ca3f"
    assert_error(changed, "commit assessment revision is outside reviewed ancestry")

    changed = document
    feature(changed, "watch").dig("specification_history", "changes", 0, "diff_paths").clear
    assert_error(changed, "semantic diff paths must be a non-empty")

    changed = document
    feature(changed, "watch").dig("specification_history", "changes", 0)["from_revision"] =
      "65d41edf381afb9c18e01e55332a293332f340e6"
    assert_error(changed, "semantic boundary revision drift")
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def test_each_authoritative_semantic_commit_cannot_be_removed_or_reclassified
    registry = document
    validator = Ibex::Quality::Maturity.new(today: TODAY)
    Ibex::Quality::Maturity::SEMANTIC_COMMIT_AUTHORITIES.each do |id, boundaries|
      history = feature(registry, id).dig("specification_history", "changes")
      boundaries.each do |boundary, semantic_revisions|
        assessments = history.find { |change| change.fetch("boundary") == boundary }.fetch("commit_assessments")
        semantic_revisions.each do |revision|
          removed = assessments.reject { |assessment| assessment.fetch("revision") == revision }
          assert_raises(RuntimeError, "#{id} #{boundary} must reject removing #{revision}") do
            validator.send(:verify_commit_assessment_authority, id, boundary, removed)
          end

          reclassified = assessments.map(&:dup)
          reclassified.find { |assessment| assessment.fetch("revision") == revision }["classification"] =
            "internal_refactor"
          assert_raises(RuntimeError, "#{id} #{boundary} must reject reclassifying #{revision}") do
            validator.send(:verify_commit_assessment_authority, id, boundary, reclassified)
          end
        end
      end
    end
  end

  def test_known_guarded_or_lazy_load_commits_cannot_be_promoted_to_semantic
    registry = document
    validator = Ibex::Quality::Maturity.new(today: TODAY)
    KNOWN_NONSEMANTIC_MAPPINGS.each do |id, boundaries|
      history = feature(registry, id).dig("specification_history", "changes")
      boundaries.each do |boundary, revisions|
        assessments = history.find { |change| change.fetch("boundary") == boundary }.fetch("commit_assessments")
        revisions.each do |revision|
          promoted = assessments.map(&:dup)
          assessment = promoted.find { |entry| entry.fetch("revision") == revision }
          refute_equal "semantic_change", assessment.fetch("classification")
          assessment["classification"] = "semantic_change"
          assert_raises(RuntimeError, "#{id} #{boundary} must reject promoting #{revision}") do
            validator.send(:verify_commit_assessment_authority, id, boundary, promoted)
          end
        end
      end
    end
  end

  def test_source_digest_changes_are_integrity_evidence_not_semantic_conclusions
    ebnf = feature(document, "ebnf-groups").fetch("specification_history")
    refute_equal ebnf.dig("snapshots", 0, "source_tree_sha256"), ebnf.dig("snapshots", 1, "source_tree_sha256")
    assert_equal "no_semantic_change", ebnf.dig("changes", 1, "classification")

    lexers = feature(document, "generated-lexers").fetch("specification_history")
    refute_equal lexers.dig("snapshots", 1, "source_tree_sha256"),
                 lexers.dig("snapshots", 2, "source_tree_sha256")
    assert_equal "no_semantic_change", lexers.dig("changes", 1, "classification")
    refute_empty lexers.dig("changes", 1, "commit_assessments")
  end

  # rubocop:disable Metrics/AbcSize -- mutations cover every structured-decision field family.
  def test_rejects_unstructured_or_test_only_decisions
    changed = document
    feature(changed, "watch")["decision"]["reason"] = "Tests pass."
    assert_error(changed, "passing tests alone")

    changed = document
    feature(changed, "watch")["decision"]["reason"] = "The implementation exists."
    assert_error(changed, "implementation or passing tests alone")

    %w[user_problem kill_condition].each do |field|
      changed = document
      feature(changed, "lsp")["decision"][field] = ""
      assert_error(changed, "decision #{field} must be a non-empty")
    end

    changed = document
    feature(changed, "lsp").dig("decision", "alternatives").clear
    assert_error(changed, "decision alternatives must be a non-empty")

    changed = document
    feature(changed, "lsp").dig("decision", "evidence").clear
    assert_error(changed, "decision evidence must be a non-empty")

    changed = document
    feature(changed, "lsp")["decision"]["value_classification"] = "public_real"
    assert_error(changed, "value classification drifts from workload evidence")

    changed = document
    feature(changed, "semantic-locations-types")["decision"]["redesign_plan"] = "not_applicable"
    assert_error(changed, "redesign requires an explicit split plan")
  end
  # rubocop:enable Metrics/AbcSize

  def test_rejects_activation_boundary_drift
    changed = document
    feature(changed, "middle-actions").dig("activation", "surfaces", 0)["default_enabled"] = false
    assert_error(changed, "activation surfaces drift")

    changed = document
    feature(changed, "semantic-locations-types").dig("activation", "surfaces").pop
    assert_error(changed, "activation surfaces drift")

    changed = document
    overlap = feature(changed, "middle-actions").dig("activation", "stable_overlap")
    overlap["breaking_policy"] = "preview_notice"
    assert_error(changed, "Stable guarantee must govern")

    changed = document
    decision = feature(changed, "middle-actions").fetch("decision")
    decision["outcome"] = "keep"
    decision["criteria_status"] = "unmet"
    decision["redesign_plan"] = "not_applicable"
    assert_error(changed, "cannot be kept as a breaking Preview surface")

    changed = document
    feature(changed, "middle-actions")["decision"]["reason"] =
      "The compatible surface can break under Preview notice despite its Stable contract."
    assert_error(changed, "Stable guarantee takes precedence")
  end

  def test_rejects_wrong_feature_budget_or_release_dependency_state
    changed = document
    changed.fetch("budgets")["experimental_product_features"] = 1
    assert_error(changed, "budgets do not match")

    changed = document
    changed.dig("release_dependencies", "R002")["status"] = "complete"
    assert_error(changed, "R002 dependency status drift")

    changed = document
    feature(changed, "bounded-repair").dig("release_gate", "blockers").delete("R001")
    assert_error(changed, "release blockers must be exactly R001 and R002")
  end

  def test_rejects_missing_evidence_and_source_digest_drift
    changed = document
    feature(changed, "coverage").dig("documentation", "evidence")[0] = "docs/missing.md"
    assert_error(changed, "path is missing")

    changed = document
    feature(changed, "coverage").dig("sources", 0)["sha256"] = "0" * 64
    assert_error(changed, "source digest drift")

    changed = document
    feature(changed, "ebnf-groups")["sources"] = feature(changed, "parameterized-rules")["sources"].map(&:dup)
    assert_error(changed, "authoritative canonical source path set drift")

    changed = document
    feature(changed, "semantic-locations-types").fetch("sources").shift
    assert_error(changed, "authoritative canonical source path set drift")
  end

  def test_trusted_syntax_profile_mutation_fails_canonical_source_verification
    registry = document
    sources = feature(registry, "incremental-cst").fetch("sources")
    expected_paths = Ibex::Quality::Maturity::CANONICAL_SOURCES.fetch("incremental-cst")
    actual_paths = sources.map { |source| source.fetch("path") }
    assert_equal expected_paths, actual_paths
    assert_includes expected_paths, "lib/ibex/runtime/syntax_session.rb"

    with_mutated_trust_profile(registry, sources) do |validator|
      error = assert_raises(RuntimeError) do
        validator.send(:verify_sources, "incremental-cst", sources)
      end
      assert_includes error.message, "source digest drift for lib/ibex/runtime/syntax_session.rb"
    end
  end

  def test_rejects_hidden_redesign_or_removal_when_public_summary_is_unchanged
    %w[redesign remove].each do |outcome|
      changed = document
      feature(changed, "browser-playground")["decision"]["outcome"] = outcome
      expected = outcome == "redesign" ? "redesign retains current maturity" : "reviewed maturity decision drift"
      assert_error(changed, expected)
    end
  end

  def test_rejects_narrative_or_stability_summary_drift
    Dir.mktmpdir("maturity-narrative-test-") do |directory|
      narrative = File.join(directory, "maturity.md")
      File.write(narrative, File.read(NARRATIVE).sub("`ebnf-groups`", "`ebnf-group`"))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Maturity.new(narrative: narrative, today: TODAY).verify!
      end
      assert_includes error.message, "maturity summary drift"
    end

    Dir.mktmpdir("maturity-stability-test-") do |directory|
      stability = File.join(directory, "stability.md")
      source = File.read(File.join(ROOT, "docs/policy/stability.md")).sub("Keep Experimental", "Retain Experimental")
      File.write(stability, source)
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Maturity.new(stability: stability, today: TODAY).verify!
      end
      assert_includes error.message, "maturity summary drift"
    end
  end

  private

  def with_mutated_trust_profile(registry, sources)
    Dir.mktmpdir("maturity-trust-profile-") do |root|
      copy_maturity_sources(root, sources)
      syntax_session = File.join(root, "lib/ibex/runtime/syntax_session.rb")
      mutated = File.binread(syntax_session)
      replacement = mutated.sub!(
        "TRUSTED_PROFILE = :trusted_application_code",
        "TRUSTED_PROFILE = :unreviewed_application_code"
      )
      raise "trusted profile fixture is missing" unless replacement

      File.binwrite(syntax_session, mutated)
      yield isolated_source_validator(root, registry, sources)
    end
  end

  def copy_maturity_sources(root, sources)
    sources.each do |source|
      relative = source.fetch("path")
      target = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(ROOT, relative), target)
    end
  end

  def isolated_source_validator(root, registry, sources)
    revision = registry.dig("audit", "reviewed_repository_revision")
    git_objects = sources.to_h do |source|
      relative = source.fetch("path")
      [[revision, relative], File.binread(File.join(ROOT, relative))]
    end
    validator = Ibex::Quality::Maturity.new(root: root, today: TODAY)
    validator.instance_variable_set(:@reviewed_revision, revision)
    validator.instance_variable_set(:@git_objects, git_objects)
    validator
  end

  def document
    YAML.safe_load_file(REGISTRY, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def feature(value, id)
    value.fetch("features").find { |record| record.fetch("id") == id }
  end

  def issue_record(feature_ids:, rationale: nil)
    {
      "number" => 123,
      "title" => "Example issue",
      "url" => "https://github.com/ydah/ibex/issues/123",
      "disposition" => { "feature_ids" => feature_ids, "not_applicable_rationale" => rationale }
    }
  end

  def assert_error(value, message, today: TODAY)
    Dir.mktmpdir("maturity-registry-test-") do |directory|
      registry = File.join(directory, "maturity.yml")
      File.write(registry, YAML.dump(value))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::Maturity.new(registry: registry, today: today).verify!
      end
      assert_includes error.message, message
    end
  end
end
# rubocop:enable Metrics/ClassLength
