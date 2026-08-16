# frozen_string_literal: true

require "json_schemer"
require_relative "../error_ux_snapshot"
require_relative "comparative_claims"
require_relative "error_ux_review/bindings"
require_relative "error_ux_review/identity"
require_relative "error_ux_review/publication"
require_relative "error_ux_review/record_validator"
require_relative "error_ux_review/template"

module Ibex
  module Quality
    # Owns the immutable R001 kit, imported review records, and truthful gate state.
    class ErrorUXReview
      include ErrorUXReviewIdentity

      ROOT = File.expand_path("../..", __dir__)
      STATUS = "docs/evidence/error-ux-review-status-v1.json"
      SNAPSHOT_SCHEMA = "schema/error-ux-v1.schema.json"

      def initialize(root: ROOT, status: STATUS, fetcher: ErrorUXReviewStrictFetcher.new,
                     snapshot_checker: -> { ErrorUXSnapshot.verify? })
        @root = File.expand_path(root)
        @status_path = ErrorUXReviewIdentity.repository_path(@root, status, "review status")
        @fetcher = fetcher
        @snapshot_checker = snapshot_checker
      end

      def verify_kit!
        document = ErrorUXReviewIdentity.parse_json(@status_path, "review status")
        verify_status_contract!(document)
        verify_assets!(document.fetch("kit"))
        records = verify_records!(document.fetch("kit"), document.fetch("records"))
        verify_gate_state!(document, records)
        @records = records
        @document = document
        document
      end

      def status_line
        verify_kit! unless @document
        current_status_line
      end

      def release_gate!
        verify_kit! unless @document
        unless @document.fetch("status") == "PASS"
          raise "#{current_status_line}; a valid published external record is required for release promotion"
        end

        ComparativeClaims.new(root: @root).verify!
        verifier = ErrorUXReviewRemoteVerifier.new(fetcher: @fetcher)
        @records.each do |item|
          verifier.verify!(item.fetch(:registration), item.fetch(:bytes), item.fetch(:record))
        end
        current_status_line
      end

      def write_template!(path)
        verify_kit!
        absolute = File.expand_path(path)
        ErrorUXReviewTemplate.new(root: @root, kit: @document.fetch("kit")).write!(absolute)
      end

      private

      def current_status_line
        "#{@document.fetch('status')} #{@document.fetch('gate_id')}: #{@document.fetch('reason')}"
      end

      def verify_status_contract!(document)
        ErrorUXReviewIdentity.exact_keys!(
          document, %w[schema_version gate_id status reason kit records], "review status"
        )
        raise "review status schema_version must be 1" unless document.fetch("schema_version") == 1
        raise "review status gate_id must be R001" unless document.fetch("gate_id") == "R001"

        verify_kit_contract!(document.fetch("kit"))
        records = document.fetch("records")
        raise "review records must be an array" unless records.is_a?(Array)
      end

      def verify_kit_contract!(kit)
        keys = %w[
          id version repository_url rubric_path rubric_sha256 schema_path schema_sha256 records_directory
          maintainer_github_logins snapshot corpus_at_introduction
        ]
        ErrorUXReviewIdentity.exact_keys!(kit, keys, "review kit")
        raise "review kit ID is invalid" unless kit.fetch("id") == "ibex-error-ux-independent-review"
        raise "review kit version must be 1" unless kit.fetch("version") == 1
        raise "review repository URL is invalid" unless kit.fetch("repository_url") == "https://github.com/ydah/ibex"

        verify_maintainer_roster!(kit.fetch("maintainer_github_logins"))
        verify_snapshot_contract!(kit.fetch("snapshot"))
        ErrorUXReviewIdentity.exact_keys!(
          kit.fetch("corpus_at_introduction"),
          %w[ibex_grammar ibex_grammar_sha256 racc_grammar racc_grammar_sha256],
          "review corpus identity"
        )
      end

      def verify_maintainer_roster!(roster)
        valid = roster.is_a?(Array) && roster == roster.sort && roster.uniq == roster
        valid &&= roster.all? { |login| login.is_a?(String) && login.match?(ErrorUXReviewPublication::LOGIN) }
        raise "maintainer GitHub login roster must be canonical, ordered, and unique" unless valid
        raise "maintainer GitHub login roster must include ydah" unless roster.any? { |login| login.casecmp?("ydah") }
      end

      def verify_snapshot_contract!(snapshot)
        ErrorUXReviewIdentity.exact_keys!(
          snapshot, %w[path introduced_at_revision sha256 case_ids], "review snapshot identity"
        )
        unless snapshot.fetch("case_ids") == CASE_IDS
          raise "review snapshot must contain EUX-01 through EUX-10 in order"
        end
        unless snapshot.fetch("introduced_at_revision").match?(REVISION)
          raise "review snapshot revision must be a full SHA"
        end
        raise "review snapshot digest must be SHA-256" unless snapshot.fetch("sha256").match?(SHA256)
      end

      def verify_assets!(kit)
        ErrorUXReviewIdentity.verify_public_links!(@root)
        verify_file_digest!(kit.fetch("rubric_path"), kit.fetch("rubric_sha256"), "review rubric")
        schema_path = verify_file_digest!(kit.fetch("schema_path"), kit.fetch("schema_sha256"), "review schema")
        schema = ErrorUXReviewIdentity.parse_json(schema_path, "review schema")
        raise "review schema is not a valid JSON Schema" unless JSONSchemer.valid_schema?(schema)
        raise "review schema root must be closed" unless schema.fetch("additionalProperties") == false

        verify_snapshot!(kit)
        @record_schema = schema
      end

      def verify_snapshot!(kit)
        snapshot = kit.fetch("snapshot")
        path = verify_file_digest!(snapshot.fetch("path"), snapshot.fetch("sha256"), "review snapshot")
        document = ErrorUXReviewIdentity.parse_json(path, "review snapshot")
        schema_path = ErrorUXReviewIdentity.repository_path(@root, SNAPSHOT_SCHEMA, "snapshot schema")
        errors = JSONSchemer.schema(JSON.parse(File.binread(schema_path))).validate(document).to_a
        raise "review snapshot schema violation: #{errors.first.inspect}" unless errors.empty?

        ids = document.fetch("cases").map { |entry| entry.fetch("id") }
        raise "review snapshot case IDs changed" unless ids == snapshot.fetch("case_ids")

        verify_introduction_identity!(kit)
        raise "review snapshot regeneration is stale" unless @snapshot_checker.call
      end

      def verify_introduction_identity!(kit)
        revision = kit.dig("snapshot", "introduced_at_revision")
        snapshot_source = ErrorUXReviewIdentity.git_show(@root, revision, kit.dig("snapshot", "path"))
        raise "review snapshot introduction digest changed" unless
          ErrorUXReviewIdentity.digest(snapshot_source) == kit.dig("snapshot", "sha256")

        corpus = kit.fetch("corpus_at_introduction")
        %w[ibex racc].each do |name|
          path = corpus.fetch("#{name}_grammar")
          digest = ErrorUXReviewIdentity.digest(ErrorUXReviewIdentity.git_show(@root, revision, path))
          raise "#{name} grammar introduction digest changed" unless digest == corpus.fetch("#{name}_grammar_sha256")
        end
      end

      def verify_records!(kit, registry)
        paths = registry.map { |entry| entry.fetch("record_path") }
        raise "review record registrations must be ordered and unique" unless paths == paths.sort && paths.uniq == paths

        directory = ErrorUXReviewIdentity.repository_path(@root, kit.fetch("records_directory"), "records directory")
        actual = Dir.glob(File.join(directory, "*.json")).map { |path| path.delete_prefix("#{@root}/") }
        raise "registered review paths do not match imported JSON files" unless actual == paths

        validator = ErrorUXReviewRecordValidator.new(root: @root, kit: kit, schema: @record_schema)
        publication = ErrorUXReviewPublication.new(root: @root, kit: kit)
        registry.map do |entry|
          verify_registered_record!(entry, validator, publication)
        end
      end

      def verify_registered_record!(entry, validator, publication)
        relative = entry.fetch("record_path")
        path = ErrorUXReviewIdentity.repository_path(@root, relative, "review record")
        expected = entry.fetch("sha256")
        raise "#{relative}: registered digest must be SHA-256" unless expected.match?(SHA256)
        raise "#{relative}: registered digest mismatch" unless ErrorUXReviewIdentity.file_digest(path) == expected

        bytes = File.binread(path)
        record = ErrorUXReviewIdentity.parse_json(path, relative)
        validator.verify!(record, path: relative)
        publication.verify!(entry, record)
        { registration: entry, record: record, bytes: bytes }
      end

      def verify_gate_state!(document, records)
        expected = records.empty? ? %w[HOLD awaiting_independent_review] : %w[PASS independent_review_published]
        actual = document.values_at("status", "reason")
        raise "R001 status must be #{expected.join('/')} for the registered review records" unless actual == expected

        ErrorUXReviewBindings.verify_claim_state!(@root, document.fetch("status"), document.fetch("records"))
        ErrorUXReviewBindings.verify_report_bindings!(@root, document.fetch("status"), document.fetch("records"))
        ComparativeClaims.new(root: @root).verify! if document.fetch("status") == "PASS"
      end

      def verify_file_digest!(relative, expected, label)
        raise "#{label} digest must be SHA-256" unless expected.match?(SHA256)

        path = ErrorUXReviewIdentity.repository_path(@root, relative, label)
        raise "missing #{label} #{relative}" unless File.file?(path)
        raise "#{label} digest mismatch" unless ErrorUXReviewIdentity.file_digest(path) == expected

        path
      end
    end
  end
end
