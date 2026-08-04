# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/error_ux_review/publication"
require "date"
require "fileutils"
require "tmpdir"

class ErrorUXReviewPublicationTest < Minitest::Test
  Response = Struct.new(:code, :body, :location) do
    def [](name)
      name.downcase == "location" ? location : nil
    end
  end

  def test_accepts_only_a_canonical_full_sha_blob_identity
    with_publication do |publication, registration, record|
      assert_kind_of Hash, publication.verify!(registration, record)
    end
  end

  def test_rejects_mutable_ambiguous_and_noncanonical_urls
    invalid = [
      "https://github.com/example-reviewer/error-reviews/blob/main/reviews/error-ux-v1.json",
      "https://github.com/example-reviewer/error-reviews/blob/v1/reviews/error-ux-v1.json",
      "https://github.com/example-reviewer/error-reviews/commit/#{'a' * 40}",
      "https://github.com/example-reviewer/error-reviews/issues/1",
      "https://github.com/example-reviewer/error-reviews/pull/1#issuecomment-2",
      "https://github.com/example-reviewer/error-reviews/releases/tag/v1",
      "#{permalink}?raw=1",
      "#{permalink}#readme",
      "https://github.com/example-reviewer/error-reviews/blob/#{'a' * 40}/reviews/%2e%2e/review.json",
      "https://github.com/example-reviewer/error-reviews/blob/#{'a' * 39}/reviews/error-ux-v1.json",
      "https://github.com/example-reviewer/error-reviews/blob/#{'A' * 40}/reviews/error-ux-v1.json"
    ]
    invalid.each do |url|
      with_publication do |publication, registration, record|
        registration["permalink"] = url
        assert_raises(RuntimeError, url) { publication.verify!(registration, record) }
      end
    end
  end

  def test_rejects_owner_repository_revision_path_and_raw_identity_mismatches
    %w[owner repository revision path raw_url].each do |key|
      with_publication do |publication, registration, record|
        registration.fetch("source")[key] = "wrong"
        assert_raises(RuntimeError, key) { publication.verify!(registration, record) }
      end
    end
  end

  def test_source_owner_must_equal_publisher_and_reviewer_login
    with_publication do |publication, registration, record|
      registration["permalink"].sub!("example-reviewer", "different-owner")
      source = registration.fetch("source")
      source["owner"] = "different-owner"
      source["raw_url"].sub!("example-reviewer", "different-owner")

      error = assert_raises(RuntimeError) { publication.verify!(registration, record) }
      assert_includes error.message, "source owner, publisher, and independent reviewer"
    end

    with_publication do |publication, registration, record|
      registration["permalink"].sub!("example-reviewer", "EXAMPLE-REVIEWER")
      source = registration.fetch("source")
      source["owner"] = "EXAMPLE-REVIEWER"
      source["raw_url"].sub!("example-reviewer", "EXAMPLE-REVIEWER")

      assert publication.verify!(registration, record)
    end
  end

  def test_rejects_alias_rostered_and_nonreviewer_publishers
    ["@example-reviewer", "https://github.com/example-reviewer", "other-reviewer", "YDAH"].each do |login|
      with_publication do |publication, registration, record|
        registration["publisher_github_login"] = login
        assert_raises(RuntimeError, login) { publication.verify!(registration, record) }
      end
    end
  end

  def test_import_vetting_requires_rostered_identity_and_exact_attestations
    with_publication do |publication, registration, record|
      registration.fetch("import_vetting")["source_bytes_verified"] = false
      assert_raises(RuntimeError) { publication.verify!(registration, record) }
    end
    with_publication do |publication, registration, record|
      registration.fetch("import_vetting")["publisher_account_metadata_reviewed"] = false
      assert_raises(RuntimeError) { publication.verify!(registration, record) }
    end
    with_publication do |publication, registration, record|
      registration.fetch("import_vetting")["vetted_by_github_login"] = "someone-else"
      assert_raises(RuntimeError) { publication.verify!(registration, record) }
    end
    with_publication do |publication, registration, record|
      registration.fetch("import_vetting")["vetted_on"] = (Date.today + 1).iso8601
      assert_raises(RuntimeError) { publication.verify!(registration, record) }
    end
  end

  def test_remote_verification_compares_bytes_digest_and_api_author
    with_publication do |_publication, registration, record|
      bytes = "published payload\n".b
      registration["sha256"] = Ibex::Quality::ErrorUXReviewIdentity.digest(bytes)
      fetcher = FakeFetcher.new(bytes, "EXAMPLE-REVIEWER")
      verifier = Ibex::Quality::ErrorUXReviewRemoteVerifier.new(fetcher: fetcher)

      assert verifier.verify!(registration, bytes, record)

      fetcher.bytes = "changed"
      assert_raises(RuntimeError) { verifier.verify!(registration, bytes, record) }

      fetcher.bytes = bytes
      fetcher.login = "other"
      assert_raises(RuntimeError) { verifier.verify!(registration, bytes, record) }

      fetcher.login = "example-reviewer"
      registration.fetch("source")["owner"] = "different-owner"
      error = assert_raises(RuntimeError) { verifier.verify!(registration, bytes, record) }
      assert_includes error.message, "source owner"
    end
  end

  def test_strict_fetcher_rejects_redirect_and_non_200_responses
    source = registration_template.fetch("source")
    redirect = Ibex::Quality::ErrorUXReviewStrictFetcher.new(
      transport: ->(_uri, _request) { Response.new("302", "", "https://example.test/other") }
    )
    error = assert_raises(RuntimeError) { redirect.blob_bytes(source) }
    assert_includes error.message, "redirected ambiguously"

    missing = Ibex::Quality::ErrorUXReviewStrictFetcher.new(
      transport: ->(_uri, _request) { Response.new("404", "missing", nil) }
    )
    error = assert_raises(RuntimeError) { missing.blob_bytes(source) }
    assert_includes error.message, "HTTP 404"
  end

  FakeFetcher = Struct.new(:bytes, :login) do
    def blob_bytes(_source)
      bytes
    end

    def commit_author(_source)
      login
    end
  end

  private

  def permalink
    "https://github.com/example-reviewer/error-reviews/blob/#{'a' * 40}/reviews/error-ux-v1.json"
  end

  def registration_template
    {
      "record_path" => "records/review.json",
      "sha256" => "0" * 64,
      "permalink" => permalink,
      "source" => {
        "owner" => "example-reviewer",
        "repository" => "error-reviews",
        "revision" => "a" * 40,
        "path" => "reviews/error-ux-v1.json",
        "raw_url" => "https://raw.githubusercontent.com/example-reviewer/error-reviews/#{'a' * 40}/" \
                     "reviews/error-ux-v1.json"
      },
      "publisher_github_login" => "example-reviewer",
      "import_vetting" => {
        "vetted_by_github_login" => "ydah",
        "vetted_on" => Date.today.iso8601,
        "source_bytes_verified" => true,
        "publisher_account_metadata_reviewed" => true
      }
    }
  end

  def with_publication
    Dir.mktmpdir("error-ux-publication-") do |root|
      FileUtils.mkdir_p(File.join(root, "records"))
      File.binwrite(File.join(root, "records/review.json"), "published payload\n")
      kit = { "records_directory" => "records", "maintainer_github_logins" => ["ydah"] }
      record = { "reviewer" => { "github_login" => "example-reviewer" } }
      yield Ibex::Quality::ErrorUXReviewPublication.new(root: root, kit: kit), registration_template, record
    end
  end
end
