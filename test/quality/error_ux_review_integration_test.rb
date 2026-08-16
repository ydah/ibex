# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/error_ux_review"
require "date"
require "fileutils"
require "tmpdir"
require "yaml"

# rubocop:disable Metrics/ClassLength -- one temp-repository scenario owns every cross-file PASS binding.
class ErrorUXReviewIntegrationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  OVERLAY = %w[
    README.md docs/registry/claims.yml docs/evidence/error-ux.md docs/evidence/error-ux-review-rubric-v1.md
    docs/evidence/error-ux-review-status-v1.json docs/records/error-ux/reviews/v1/records/README.md
    docs/policy/comparison-policy.md docs/policy/release-readiness.md schema/error-ux-review-v1.schema.json
  ].freeze
  FakeFetcher = Struct.new(:bytes, :login) do
    def blob_bytes(_source)
      bytes
    end

    def commit_author(_source)
      login
    end
  end

  def test_pass_requires_status_reports_claim_and_remote_identity_to_agree
    with_repository do |root|
      payload, registration = stage_payload_and_pass_status(root)
      review = verifier(root, payload)
      assert_error(review, "state must be measured/claim/complete")

      bind_claim!(root, registration)
      assert_error(verifier(root, payload), "status marker does not publish PASS")

      bind_report!(root, "README.md", registration)
      bind_report!(root, "docs/evidence/error-ux.md", registration)
      assert_error(verifier(root, payload), "docs/policy/release-readiness.md")

      bind_report!(root, "docs/policy/release-readiness.md", registration)
      review = verifier(root, payload)
      assert_kind_of Hash, review.verify_kit!
      assert_equal "PASS R001: independent_review_published", review.release_gate!

      assert_binding_mutations_fail(root, payload, registration)
    end
  end

  private

  def with_repository
    Dir.mktmpdir("error-ux-review-integration-") do |directory|
      root = File.join(directory, "repository")
      system("git", "clone", "--quiet", "--shared", ROOT, root) || raise("local clone failed")
      OVERLAY.each do |relative|
        target = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join(ROOT, relative), target)
      end
      yield root
    end
  end

  def stage_payload_and_pass_status(root)
    status = read_json(root, "docs/evidence/error-ux-review-status-v1.json")
    revision = Ibex::Quality::ErrorUXReviewIdentity.git_revision(root)
    template = Ibex::Quality::ErrorUXReviewTemplate.new(root: root, kit: status.fetch("kit"), revision: revision)
    payload = finalize_payload(template.build)
    bytes = "#{JSON.pretty_generate(payload)}\n".b
    relative = "docs/records/error-ux/reviews/v1/records/example-review.json"
    write(root, relative, bytes)

    registration = registration(relative, bytes)
    status["status"] = "PASS"
    status["reason"] = "independent_review_published"
    status["records"] = [registration]
    write_json(root, "docs/evidence/error-ux-review-status-v1.json", status)
    [bytes, registration]
  end

  def finalize_payload(payload)
    date = Date.today.iso8601
    payload["record_id"] = "EUXR-#{date}-example-reviewer"
    payload["record_state"] = "published"
    payload["reviewer"] = {
      "github_login" => "example-reviewer",
      "display_name" => "Example Independent Reviewer",
      "affiliation" => "Example Review Organization",
      "reviewed_on" => date,
      "conflicts" => "No project role, authorship, or financial conflict."
    }
    payload["consent"].transform_values! { true }
    payload.fetch("assessments").each do |assessment|
      assessment.fetch("diagnostic")["rationale"] = "The fixed diagnostic supports this independent label."
      assessment.fetch("repair")["rationale"] = "The fixed repair supports this independent label."
      assessment.fetch("disagreement")["rationale"] = "No disagreement with the normative observation."
    end
    payload["overall_rationale"] = "All ten fixed cases were reproduced and reviewed independently."
    payload
  end

  def registration(relative, bytes)
    revision = "a" * 40
    path = "reviews/error-ux-v1.json"
    {
      "record_path" => relative,
      "sha256" => Ibex::Quality::ErrorUXReviewIdentity.digest(bytes),
      "permalink" => "https://github.com/example-reviewer/error-reviews/blob/#{revision}/#{path}",
      "source" => {
        "owner" => "example-reviewer", "repository" => "error-reviews", "revision" => revision, "path" => path,
        "raw_url" => "https://raw.githubusercontent.com/example-reviewer/error-reviews/#{revision}/#{path}"
      },
      "publisher_github_login" => "example-reviewer",
      "import_vetting" => {
        "vetted_by_github_login" => "ydah", "vetted_on" => Date.today.iso8601,
        "source_bytes_verified" => true, "publisher_account_metadata_reviewed" => true
      }
    }
  end

  def bind_claim!(root, registration) # rubocop:disable Metrics/AbcSize -- explicit fixture mirrors the closed claim.
    registry = YAML.safe_load_file(File.join(root, "docs/registry/claims.yml"), permitted_classes: [], aliases: false)
    claim = registry.fetch("claims").find { |entry| entry["id"] == "racc-error-ux-json-v1" }
    claim["state"] = "measured"
    claim.fetch("binding")["kind"] = "claim"
    claim.fetch("subjective_review")["state"] = "complete"
    claim.fetch("subjective_review")["method"] = "GitHub reviewer example-reviewer assessed all ten fixed cases."
    claim["wording"] = completed_wording
    claim.fetch("evidence") << {
      "kind" => "report", "path" => registration.fetch("record_path"),
      "description" => "Byte-identical published independent review payload."
    }
    claim.fetch("evidence").sort_by! { |entry| entry.fetch("path") }
    claim.fetch("limitations").reject! { |text| text.include?("Independent subjective review is still missing") }
    claim.fetch("limitations") << Ibex::Quality::ErrorUXReviewBindings::HUMAN_LIMITATION unless
      claim.fetch("limitations").include?(Ibex::Quality::ErrorUXReviewBindings::HUMAN_LIMITATION)
    provenance = "Published review provenance: #{registration.fetch('permalink')} "
    claim.fetch("limitations") << "#{provenance}(SHA-256 #{registration.fetch('sha256')})."

    racc = registry.fetch("comparison_set").find { |entry| entry["id"] == "racc" }
    racc.merge!(Ibex::Quality::ClaimStates.comparison_state("racc", registry.fetch("claims")))

    update_comparative_block!(root, claim)
    clean_stale_report_text!(root)
    claim.fetch("binding")["body_sha256"] = comparative_body_digest(root)
    File.write(File.join(root, "docs/registry/claims.yml"), YAML.dump(registry))
  end

  def update_comparative_block!(root, claim)
    path = File.join(root, "docs/evidence/error-ux.md")
    source = File.binread(path)
    source.gsub!("comparative-evidence:racc-error-ux-json-v1", "comparative-claim:racc-error-ux-json-v1")
    start = "<!-- comparative-claim:racc-error-ux-json-v1:start -->"
    source.sub!(/#{Regexp.escape(start)}\n.*?\n\n/m, "#{start}\n#{claim.fetch('wording')}\n\n")
    File.binwrite(path, source)
  end

  def clean_stale_report_text!(root)
    Ibex::Quality::ErrorUXReviewBindings::REPORTS.each do |relative|
      path = File.join(root, relative)
      source = File.binread(path)
      Ibex::Quality::ErrorUXReviewBindings::STALE_PASS_TEXT.each do |text|
        source.gsub!(/#{Regexp.escape(text)}/i, "independent review is published")
      end
      File.binwrite(path, source)
    end
  end

  def comparative_body_digest(root)
    source = File.binread(File.join(root, "docs/evidence/error-ux.md"))
    start = "<!-- comparative-claim:racc-error-ux-json-v1:start -->"
    finish = "<!-- comparative-claim:racc-error-ux-json-v1:end -->"
    body = source.split(start, 2).last.split(finish, 2).first.delete_prefix("\n")
    Ibex::Quality::ClaimPublications.body_sha256(body)
  end

  def completed_wording
    "At Ibex revision cc20c5eb799cc218ebea665df64261f10d030f75, on ten fixed malformed JSON inputs, " \
      "the committed Ibex and Racc 1.8.1 observations and the published review by GitHub user " \
      "example-reviewer record diagnostic and repair judgments; this subjective fixed-corpus review " \
      "does not generalize."
  end

  def bind_report!(root, relative, registration)
    path = File.join(root, relative)
    source = File.binread(path)
    status_link = if relative == "README.md"
                    "docs/evidence/error-ux-review-status-v1.json"
                  else
                    "error-ux-review-status-v1.json"
                  end
    body = <<~MARKER.chomp
      R001: `PASS`

      Status: [registry](#{status_link})
      Record: `#{registration.fetch('record_path')}`
      SHA-256: `#{registration.fetch('sha256')}`
      Permalink: #{registration.fetch('permalink')}
    MARKER
    source.sub!(/<!-- r001-review-status:start -->.*?<!-- r001-review-status:end -->/m,
                "<!-- r001-review-status:start -->\n#{body}\n<!-- r001-review-status:end -->")
    File.binwrite(path, source)
  end

  def assert_binding_mutations_fail(root, payload, registration)
    assert_provenance_mutations_fail(root, payload, registration)
    assert_comparison_state_mutations_fail(root, payload)

    changed = FakeFetcher.new("different bytes", "example-reviewer")
    assert_raises(RuntimeError) { verifier(root, changed).release_gate! }
  end

  def assert_provenance_mutations_fail(root, payload, registration)
    assert_mutation_fails(root, payload, "README.md", "missing record provenance") do |source|
      source.sub(registration.fetch("permalink"), "")
    end
    assert_json_mutation_fails(root, payload, "registered digest mismatch") do |status|
      status.fetch("records").first["sha256"] = "0" * 64
    end
    assert_source_owner_mutation_fails(root, payload)
    assert_yaml_mutation_fails(root, payload, "missing R001 evidence") do |claims|
      claim = claims.fetch("claims").find { |entry| entry["id"] == "racc-error-ux-json-v1" }
      claim.fetch("evidence").reject! { |entry| entry["path"] == registration.fetch("record_path") }
    end
    assert_yaml_mutation_fails(root, payload, "human-review limitation") do |claims|
      claim = claims.fetch("claims").find { |entry| entry["id"] == "racc-error-ux-json-v1" }
      claim.fetch("limitations").delete(Ibex::Quality::ErrorUXReviewBindings::HUMAN_LIMITATION)
    end
    assert_mutation_fails(root, payload, registration.fetch("record_path"), "registered digest mismatch") do |source|
      "#{source} "
    end
  end

  def assert_source_owner_mutation_fails(root, payload)
    assert_json_mutation_fails(root, payload, "source owner, publisher, and independent reviewer") do |status|
      registration = status.fetch("records").first
      registration["permalink"].sub!("example-reviewer", "different-owner")
      registration.fetch("source")["owner"] = "different-owner"
      registration.fetch("source").fetch("raw_url").sub!("example-reviewer", "different-owner")
    end
  end

  def assert_comparison_state_mutations_fail(root, payload)
    assert_yaml_mutation_fails(root, payload, "Racc state is stale") do |claims|
      claims.fetch("comparison_set").find { |entry| entry["id"] == "racc" }["state"] = "compared"
    end
    assert_yaml_mutation_fails(root, payload, "Racc pending_claims is stale") do |claims|
      racc = claims.fetch("comparison_set").find { |entry| entry["id"] == "racc" }
      racc.fetch("pending_claims").unshift("racc-error-ux-json-v1")
    end
    assert_yaml_mutation_fails(root, payload, "Racc reason is stale") do |claims|
      racc = claims.fetch("comparison_set").find { |entry| entry["id"] == "racc" }
      racc["reason"] = "Error-UX review is pending and the formal performance result artifact is absent."
    end
  end

  def assert_mutation_fails(root, payload, relative, message)
    path = File.join(root, relative)
    original = File.binread(path)
    File.binwrite(path, yield(original))
    assert_error(verifier(root, payload), message)
  ensure
    File.binwrite(path, original) if original
  end

  def assert_json_mutation_fails(root, payload, message, &block)
    assert_mutation_fails(root, payload, "docs/evidence/error-ux-review-status-v1.json", message) do |source|
      document = JSON.parse(source)
      block.call(document)
      "#{JSON.pretty_generate(document)}\n"
    end
  end

  def assert_yaml_mutation_fails(root, payload, message, &block)
    assert_mutation_fails(root, payload, "docs/registry/claims.yml", message) do |source|
      document = YAML.safe_load(source, permitted_classes: [], aliases: false)
      block.call(document)
      YAML.dump(document)
    end
  end

  def verifier(root, payload_or_fetcher)
    fetcher = if payload_or_fetcher.respond_to?(:blob_bytes)
                payload_or_fetcher
              else
                FakeFetcher.new(payload_or_fetcher, "example-reviewer")
              end
    Ibex::Quality::ErrorUXReview.new(root: root, fetcher: fetcher, snapshot_checker: -> { true })
  end

  def assert_error(review, message)
    error = assert_raises(RuntimeError) { review.verify_kit! }
    assert_includes error.message, message
  end

  def read_json(root, relative)
    JSON.parse(File.binread(File.join(root, relative)))
  end

  def write_json(root, relative, document)
    write(root, relative, "#{JSON.pretty_generate(document)}\n")
  end

  def write(root, relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
  end
end
# rubocop:enable Metrics/ClassLength
