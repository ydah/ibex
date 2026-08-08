# frozen_string_literal: true

require "digest"
require "json"
require "json_schemer"
require_relative "../error_ux_round2/capture"
require_relative "error_ux_round2/review_registry"

module Ibex
  module Quality
    # Verifies the deterministic H003 repository capture and its HOLD boundary.
    class ErrorUXRound2
      SCHEMA = "schema/error-ux-round2-v1.schema.json"

      def initialize(root: Ibex::ErrorUXRound2::ROOT, evidence: nil, review_registry: nil, output: $stdout)
        @root = File.expand_path(root)
        @evidence = evidence || File.join(@root, "docs/error-ux-round2-v1.json")
        @review_registry = review_registry || File.join(@root, "docs/error-ux-round2-review-status-v1.json")
        @output = output
      end

      def verify! # rubocop:disable Naming/PredicateMethod -- verifier convention raises on failure.
        document = JSON.parse(File.binread(@evidence))
        validate_schema!(document)
        validate_implementation_closure!(document)
        validate_coverage!(document)
        validate_continuation!(document)
        validate_lexer_failure!(document)
        validate_review_boundary!(document)
        validate_fresh_outcomes!(document)
        validate_r001_snapshot!(document)
        validate_regeneration!(document)
        review_status = validate_external_review_registry!(document)
        @output.puts "verified H003 repository capture; external subjective gate remains HOLD; " \
                     "external review registry is #{review_status}"
        true
      end

      private

      def validate_schema!(document)
        schema = JSONSchemer.schema(JSON.parse(File.binread(File.join(@root, SCHEMA))))
        errors = schema.validate(document).to_a
        raise "H003 evidence violates schema: #{errors.first.inspect}" unless errors.empty?
      end

      def validate_implementation_closure!(document)
        expected = capture.implementation_sources
        actual = document.dig("repository_capture", "implementation_sources")
        expected_paths = expected.map { |entry| entry.fetch("path") }
        actual_paths = actual.map { |entry| entry.fetch("path") }
        raise "H003 implementation source inventory drift" unless actual_paths == expected_paths

        expected.zip(actual).each do |expected_entry, actual_entry|
          next if expected_entry.fetch("sha256") == actual_entry.fetch("sha256")

          raise "H003 implementation source digest drift: #{expected_entry.fetch('path')}"
        end
      end

      def validate_coverage!(document)
        cases = document.fetch("cases")
        ids = cases.map { |item| item.fetch("id") }
        raise "H003 case identifiers must be unique" unless ids.uniq == ids
        raise "H003 repository case count drift" unless document.dig("repository_capture", "case_count") == cases.length

        required = document.dig("problem", "required_dimensions")
        observed = cases.flat_map { |item| item.fetch("dimensions") }.uniq
        missing = required - observed
        extra = observed - required
        return if missing.empty? && extra.empty?

        raise "H003 dimension coverage drift: missing=#{missing.sort}, extra=#{extra.sort}"
      end

      def validate_continuation!(document)
        item = cases_for(document, "multi-error-continuation").fetch(0)
        observation = item.fetch("observation")
        unless observation.values_at("mode", "parse_status") ==
               %w[synchronized-continuation accepted-after-recovery]
          raise "H003 multi-error case must use synchronized continuation"
        end

        offsets = observation.fetch("diagnostics").map { |entry| entry.dig("location", "start_byte") }
        raise "H003 continuation must expose at least two distinct diagnostics" unless
          offsets.length >= 2 && offsets.all?(Integer) && offsets.each_cons(2).all? { |left, right| left < right }
      end

      def validate_lexer_failure!(document)
        item = cases_for(document, "lexer-failure").fetch(0)
        diagnostic = item.dig("observation", "diagnostics", 0)
        expected = diagnostic.fetch("expected_tokens")
        unless diagnostic.fetch("phase") == "lexer" &&
               expected == {
                 "availability" => "not-available", "tokens" => [],
                 "reason" => "lexer-failure-precedes-parser-state"
               }
          raise "H003 lexer failure must close unavailable expected-token semantics"
        end
      end

      def validate_review_boundary!(document)
        gate = document.fetch("external_subjective_gate")
        unless gate.fetch("status") == "HOLD" && gate.fetch("records").empty?
          raise "H003 external subjective gate must remain HOLD without records"
        end
        return if document.fetch("cases").all? do |item|
          item.fetch("external_review") == { "status" => "pending", "labels" => [] }
        end

        raise "H003 pending cases must not fabricate external reviewer labels"
      end

      def validate_fresh_outcomes!(document)
        statuses = document.fetch("cases").map { |item| item.dig("fresh_reparse", "status") }
        raise "H003 must retain an accepted fresh reparse" unless statuses.include?("accepted")
        raise "H003 must retain a progress-only fresh reparse" unless statuses.include?("progress")
      end

      def validate_r001_snapshot!(document)
        path = File.join(@root, "test/fixtures/error_ux/json-errors-v1.json")
        digest = Digest::SHA256.hexdigest(File.binread(path))
        expected = Ibex::ErrorUXRound2::R001_SNAPSHOT_SHA256
        raise "R001 normative snapshot digest changed" unless digest == expected

        identity = document.dig("repository_capture", "r001_normative_snapshot")
        raise "H003 evidence does not bind the unchanged R001 snapshot" unless
          identity.values_at("sha256", "expected_sha256", "status") == [expected, expected, "unchanged"]
      end

      def validate_regeneration!(document)
        actual = "#{JSON.pretty_generate(document)}\n"
        expected = capture.render
        raise "H003 deterministic evidence drift" unless actual == expected
      end

      def capture
        @capture ||= Ibex::ErrorUXRound2::Capture.new(root: @root)
      end

      def validate_external_review_registry!(document)
        ErrorUXRound2ReviewRegistry.new(
          root: @root, evidence_path: @evidence, registry_path: @review_registry
        ).verify!(document)
      end

      def cases_for(document, dimension)
        matches = document.fetch("cases").select { |item| item.fetch("dimensions").include?(dimension) }
        raise "H003 dimension #{dimension} must have exactly one focused case" unless matches.one?

        matches
      end
    end
  end
end
