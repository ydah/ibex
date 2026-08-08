# frozen_string_literal: true

require "digest"
require "json"
require "json_schemer"

module Ibex
  module Quality
    # Validates the independent H003 review pathway without creating reviews.
    class ErrorUXRound2ReviewRegistry
      SCHEMA = "schema/error-ux-round2-review-v1.schema.json"

      attr_reader :status

      def initialize(root:, evidence_path:, registry_path:)
        @root = root
        @evidence_path = evidence_path
        @registry_path = registry_path
      end

      def verify!(evidence)
        document = JSON.parse(File.binread(@registry_path))
        validate_schema!(document)
        validate_evidence_binding!(document, evidence)
        records = document.fetch("records")
        validate_records!(document, records)
        validate_disagreements!(document, records)
        @status = document.fetch("status")
      end

      private

      def validate_schema!(document)
        schema_path = File.join(@root, SCHEMA)
        errors = JSONSchemer.schema(JSON.parse(File.binread(schema_path))).validate(document).to_a
        raise "H003 review registry violates schema: #{errors.first.inspect}" unless errors.empty?
      end

      def validate_evidence_binding!(document, evidence)
        digest = Digest::SHA256.hexdigest(File.binread(@evidence_path))
        identity = document.fetch("evidence")
        unless identity == { "path" => "docs/error-ux-round2-v1.json", "sha256" => digest }
          raise "H003 review registry evidence digest drift"
        end

        expected_ids = evidence.fetch("cases").map { |item| item.fetch("id") }
        return if document.fetch("required_case_ids") == expected_ids

        raise "H003 review registry case inventory drift"
      end

      def validate_records!(document, records)
        expected_ids = document.fetch("required_case_ids")
        digest = document.dig("evidence", "sha256")
        record_ids = records.map { |record| record.fetch("record_id") }
        raise "H003 review record identifiers must be unique" unless record_ids.uniq == record_ids

        names = records.map { |record| normalize_reviewer(record.dig("reviewer", "name")) }
        raise "H003 normalized reviewer identities must be unique" unless names.uniq == names

        records.each do |record|
          raise "H003 review record evidence digest drift" unless record.fetch("evidence_sha256") == digest

          ids = record.fetch("case_reviews").map { |item| item.fetch("case_id") }
          raise "H003 review record case inventory drift" unless ids == expected_ids
        end
      end

      def validate_disagreements!(document, records)
        reviews = records.to_h do |record|
          name = normalize_reviewer(record.dig("reviewer", "name"))
          labels = record.fetch("case_reviews").to_h do |item|
            [item.fetch("case_id"), item.fetch("label")]
          end
          [name, labels]
        end

        expected = expected_disagreement_signatures(reviews)
        actual = document.fetch("disagreements").map do |entry|
          actual_disagreement_signature(entry, reviews)
        end
        raise "H003 disagreement entries must be unique" unless actual.uniq == actual
        return if actual.sort == expected.sort

        raise "H003 disagreement inventory drift"
      end

      def expected_disagreement_signatures(reviews)
        reviews.keys.combination(2).flat_map do |left, right|
          reviews.fetch(left).filter_map do |case_id, left_label|
            right_label = reviews.fetch(right).fetch(case_id)
            next if left_label == right_label

            disagreement_signature(case_id, [[left, left_label], [right, right_label]])
          end
        end
      end

      def actual_disagreement_signature(entry, reviews)
        names = entry.fetch("reviewers").map { |name| normalize_reviewer(name) }
        raise "H003 disagreement reviewers must be distinct" unless names.uniq.length == 2
        raise "H003 disagreement references an unknown reviewer" unless names.all? { |name| reviews.key?(name) }

        case_id = entry.fetch("case_id")
        pairs = names.zip(entry.fetch("labels"))
        unless pairs.all? { |name, label| reviews.fetch(name).fetch(case_id) == label }
          raise "H003 disagreement labels do not match review records"
        end

        disagreement_signature(case_id, pairs)
      end

      def disagreement_signature(case_id, pairs)
        JSON.generate([case_id, pairs.sort_by(&:first)])
      end

      def normalize_reviewer(name)
        name.unicode_normalize(:nfkc).downcase(:fold).gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
