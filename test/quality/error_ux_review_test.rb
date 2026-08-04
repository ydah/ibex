# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/error_ux_review"
require "date"
require "fileutils"
require "json"
require "json_schemer"
require "tmpdir"

class ErrorUXReviewTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  STATUS = File.join(ROOT, "docs/error-ux-review-status-v1.json")

  def test_repository_kit_is_ready_but_release_gate_truthfully_holds
    review = Ibex::Quality::ErrorUXReview.new

    assert_kind_of Hash, review.verify_kit!
    assert_equal "HOLD R001: awaiting_independent_review", review.status_line
    error = assert_raises(RuntimeError) { review.release_gate! }
    assert_includes error.message, "valid published external record is required"
  end

  def test_template_is_deterministic_and_fixes_all_source_identities
    first = template.build
    second = template.build

    assert_equal first, second
    assert_equal "draft", first.fetch("record_state")
    ids = first.fetch("assessments").map { |entry| entry.fetch("case_id") }
    assert_equal Ibex::Quality::ErrorUXReviewIdentity::CASE_IDS, ids
    assert_equal revision, first.dig("evidence", "repository", "revision")
    assert_equal kit.dig("snapshot", "sha256"), first.dig("evidence", "snapshot", "sha256")
    assert_equal "racc version 1.8.1", first.dig("reproduction", "racc", "version")
    assert_equal ["ydah"], first.dig("independence", "reviewed_maintainer_github_logins")
    assert_equal [false, false, false, false], first.fetch("consent").values
  end

  def test_template_cleanliness_check_rejects_tracked_and_untracked_changes
    Dir.mktmpdir("error-ux-template-clean-") do |root|
      system("git", "init", "--quiet", root) || raise("git init failed")
      system("git", "-C", root, "config", "user.email", "review@example.test") || raise("git config failed")
      system("git", "-C", root, "config", "user.name", "Review Test") || raise("git config failed")
      tracked = File.join(root, "tracked.txt")
      File.write(tracked, "fixed\n")
      system("git", "-C", root, "add", "tracked.txt") || raise("git add failed")
      system("git", "-C", root, "commit", "--quiet", "-m", "fixture") || raise("git commit failed")
      checker = Ibex::Quality::ErrorUXReviewTemplate.new(root: root, kit: {})

      assert_nil checker.send(:ensure_clean_tracked_checkout!)
      File.write(tracked, "changed\n")
      assert_raises(RuntimeError) { checker.send(:ensure_clean_tracked_checkout!) }
      File.write(tracked, "fixed\n")
      File.write(File.join(root, "untracked.txt"), "new\n")
      error = assert_raises(RuntimeError) { checker.send(:ensure_clean_tracked_checkout!) }
      assert_includes error.message, "tracked or untracked"
    end
  end

  def test_closed_schema_accepts_a_complete_hypothetical_record
    assert_empty schemer.validate(valid_record).to_a
    assert_kind_of Hash, record_validator.verify!(valid_record, path: "hypothetical-independent-record.json")

    changed = valid_record
    changed["unregistered_score"] = 10
    refute_empty schemer.validate(changed).to_a
  end

  def test_draft_and_placeholders_cannot_complete_the_gate
    error = assert_raises(RuntimeError) do
      record_validator.verify!(template.build, path: "draft.json")
    end
    assert_includes error.message, "schema violation"

    placeholder = valid_record
    placeholder["overall_rationale"] = "REPLACE_WITH_APPROVAL"
    error = assert_raises(RuntimeError) do
      record_validator.verify!(placeholder, path: "placeholder.json")
    end
    assert_includes error.message, "placeholder"
  end

  def test_reviewer_identity_and_complete_maintainer_roster_are_enforced
    self_review = valid_record
    self_review.fetch("reviewer")["github_login"] = "YDAH"
    error = assert_raises(RuntimeError) do
      record_validator.verify!(self_review, path: "self-review.json")
    end
    assert_includes error.message, "rostered project maintainer"

    ["@example-reviewer", "https://github.com/example-reviewer"].each do |identity_alias|
      aliased = valid_record
      aliased.fetch("reviewer")["github_login"] = identity_alias
      refute_empty schemer.validate(aliased).to_a
    end

    incomplete_roster = valid_record
    incomplete_roster.fetch("independence")["reviewed_maintainer_github_logins"] = ["someone-else"]
    error = assert_raises(RuntimeError) do
      record_validator.verify!(incomplete_roster, path: "incomplete-roster.json")
    end
    assert_includes error.message, "does not match the public kit"
  end

  def test_case_set_and_labels_are_closed
    missing = valid_record
    missing.fetch("assessments").pop
    refute_empty schemer.validate(missing).to_a

    reordered = valid_record
    reordered.fetch("assessments").rotate!
    refute_empty schemer.validate(reordered).to_a

    diagnostic = valid_record
    diagnostic.fetch("assessments").first.fetch("diagnostic")["label"] = "unsafe"
    refute_empty schemer.validate(diagnostic).to_a

    repair = valid_record
    repair.fetch("assessments").first.fetch("repair")["label"] = "probably_useful"
    refute_empty schemer.validate(repair).to_a
  end

  def test_rationales_and_disagreements_are_required
    empty_rationale = valid_record
    empty_rationale.fetch("assessments").first.fetch("repair")["rationale"] = " "
    refute_empty schemer.validate(empty_rationale).to_a

    contradiction = valid_record
    disagreement = contradiction.fetch("assessments").first.fetch("disagreement")
    disagreement["exists"] = true
    refute_empty schemer.validate(contradiction).to_a
  end

  def test_structured_consent_and_payload_publication_separation_are_enforced
    no_consent = valid_record
    no_consent.fetch("consent")["store_identity"] = false
    refute_empty schemer.validate(no_consent).to_a

    self_referential = valid_record
    self_referential["permalink"] = "https://github.com/example/reviews/blob/#{'a' * 40}/review.json"
    refute_empty schemer.validate(self_referential).to_a
  end

  def test_source_identity_is_enforced
    drift = valid_record
    drift.dig("evidence", "corpus")["ibex_grammar_sha256"] = "0" * 64
    error = assert_raises(RuntimeError) { record_validator.verify!(drift, path: "drift.json") }
    assert_includes error.message, "does not match repository revision"
  end

  private

  def status
    @status ||= JSON.parse(File.binread(STATUS))
  end

  def kit
    status.fetch("kit")
  end

  def schema
    @schema ||= JSON.parse(File.binread(File.join(ROOT, kit.fetch("schema_path"))))
  end

  def schemer
    @schemer ||= JSONSchemer.schema(schema)
  end

  def revision
    @revision ||= Ibex::Quality::ErrorUXReviewIdentity.git_revision(ROOT)
  end

  def template
    @template ||= Ibex::Quality::ErrorUXReviewTemplate.new(root: ROOT, kit: kit, revision: revision)
  end

  def record_validator
    @record_validator ||= Ibex::Quality::ErrorUXReviewRecordValidator.new(root: ROOT, kit: kit, schema: schema)
  end

  def valid_record
    record = Marshal.load(Marshal.dump(template.build))
    date = Date.today.iso8601
    record["record_id"] = "EUXR-#{date}-example-reviewer"
    record["record_state"] = "published"
    record["reviewer"] = {
      "github_login" => "example-reviewer",
      "display_name" => "Example Independent Reviewer",
      "affiliation" => "Example Review Organization",
      "reviewed_on" => date,
      "conflicts" => "No project role, financial interest, or authorship conflict."
    }
    record["consent"] = {
      "store_identity" => true,
      "store_labels" => true,
      "store_rationales" => true,
      "republish_review" => true
    }
    record.fetch("assessments").each do |assessment|
      assessment.fetch("diagnostic")["rationale"] = "The fixed diagnostic observation supports this label."
      assessment.fetch("repair")["rationale"] = "The fixed repair plan supports this label."
      assessment.fetch("disagreement")["rationale"] = "No disagreement with the normative observation."
    end
    record["overall_rationale"] = "All ten fixed cases were reproduced and assessed independently."
    record
  end
end
