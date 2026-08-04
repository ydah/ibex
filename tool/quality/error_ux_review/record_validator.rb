# frozen_string_literal: true

require "date"
require "json_schemer"
require_relative "identity"

module Ibex
  module Quality
    class ErrorUXReviewRecordValidator
      include ErrorUXReviewIdentity

      def initialize(root:, kit:, schema:)
        @root = root
        @kit = kit
        @schema = schema
      end

      def verify!(record, path:)
        errors = JSONSchemer.schema(@schema).validate(record).to_a
        raise "#{path}: review schema violation: #{errors.first.inspect}" unless errors.empty?
        raise "#{path}: only a published review can complete R001" unless record.fetch("record_state") == "published"
        raise "#{path}: draft placeholder text cannot complete R001" if ErrorUXReviewIdentity.placeholder?(record)

        verify_record_date!(record, path)
        verify_kit_identity!(record.fetch("kit"), path)
        verify_evidence!(record, path)
        record
      end

      private

      def verify_record_date!(record, path)
        date = Date.iso8601(record.dig("reviewer", "reviewed_on"))
        raise "#{path}: review date cannot be in the future" if date > Date.today
        return if record.fetch("record_id").start_with?("EUXR-#{date.iso8601}-")

        raise "#{path}: record ID date must match reviewer.reviewed_on"
      rescue Date::Error
        raise "#{path}: reviewer.reviewed_on must be an ISO 8601 calendar date"
      end

      def verify_kit_identity!(record_kit, path)
        expected = {
          "id" => @kit.fetch("id"),
          "version" => @kit.fetch("version"),
          "rubric_path" => @kit.fetch("rubric_path"),
          "rubric_sha256" => @kit.fetch("rubric_sha256"),
          "schema_path" => @kit.fetch("schema_path"),
          "schema_sha256" => @kit.fetch("schema_sha256")
        }
        return if record_kit == expected

        raise "#{path}: review kit identity does not match the public status registry"
      end

      def verify_evidence!(record, path)
        evidence = record.fetch("evidence")
        revision = evidence.dig("repository", "revision")
        verify_snapshot!(record, revision, path)
        verify_corpus!(evidence.fetch("corpus"), revision, path)
        expected_version = JSON.parse(snapshot_at(revision)).fetch("racc_version")
        return if record.dig("reproduction", "racc", "version") == expected_version

        raise "#{path}: reproduced Racc identity does not match the reviewed snapshot"
      end

      def verify_snapshot!(record, revision, path)
        snapshot = snapshot_at(revision)
        evidence = record.fetch("evidence")
        expected_digest = @kit.dig("snapshot", "sha256")
        unless evidence.dig("snapshot", "sha256") == expected_digest &&
               ErrorUXReviewIdentity.digest(snapshot) == expected_digest
          raise "#{path}: snapshot digest does not match the immutable review kit"
        end

        document = JSON.parse(snapshot)
        ids = document.fetch("cases").map { |entry| entry.fetch("id") }
        raise "#{path}: source snapshot does not contain the exact ten case IDs" unless ids == CASE_IDS
        raise "#{path}: review record case IDs do not match the snapshot" unless evidence.fetch("case_ids") == ids

        verify_failure_rows!(document.fetch("cases"), path)
      end

      def verify_failure_rows!(cases, path)
        complete = cases.all? do |entry|
          entry.dig("ibex", "status") == "rejected" &&
            entry.dig("racc", "status") == "rejected" &&
            entry.dig("repair", "status") == "repaired"
        end
        raise "#{path}: source snapshot hides, removes, or changes a fixed failure row" unless complete
      end

      def verify_corpus!(corpus, revision, path)
        expected = {
          "ibex_grammar_sha256" => source_digest(revision, corpus.fetch("ibex_grammar")),
          "racc_grammar_sha256" => source_digest(revision, corpus.fetch("racc_grammar"))
        }
        expected.each do |key, digest|
          raise "#{path}: #{key} does not match repository revision #{revision}" unless corpus.fetch(key) == digest
        end
      end

      def snapshot_at(revision)
        ErrorUXReviewIdentity.git_show(@root, revision, @kit.dig("snapshot", "path"))
      end

      def source_digest(revision, relative)
        ErrorUXReviewIdentity.digest(ErrorUXReviewIdentity.git_show(@root, revision, relative))
      end
    end
  end
end
