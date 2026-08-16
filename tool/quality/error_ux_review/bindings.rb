# frozen_string_literal: true

require "yaml"
require_relative "../comparative_claims/identities"
require_relative "identity"

module Ibex
  module Quality
    module ErrorUXReviewBindings
      CLAIM_ID = "racc-error-ux-json-v1"
      CLAIM_EVIDENCE = %w[
        docs/evidence/error-ux-review-rubric-v1.md docs/evidence/error-ux-review-status-v1.json
        schema/error-ux-review-v1.schema.json
      ].freeze
      REPORTS = %w[README.md docs/evidence/error-ux.md docs/policy/release-readiness.md].freeze
      START_MARKER = "<!-- r001-review-status:start -->"
      END_MARKER = "<!-- r001-review-status:end -->"
      HUMAN_LIMITATION = "Independent human review remains subjective and cannot prove affiliation, conflict " \
                         "disclosure, coercion resistance, or general error UX quality."
      STALE_PASS_TEXT = [
        "awaiting_independent_review", "still needs independent review",
        "has not received independent third-party review", "independent review is still missing",
        "independent review is missing", "independent subjective review is pending",
        "do not include an independent diagnostic or repair assessment",
        "at least one external reviewer must record a review", "obtain and publish an independent review",
        "before this KPI passes"
      ].freeze

      module_function

      def verify_claim_state!(root, status, records)
        registry = YAML.safe_load_file(
          ErrorUXReviewIdentity.repository_path(root, "docs/registry/claims.yml", "comparative claim registry"),
          permitted_classes: [], aliases: false
        )
        claim = registry.fetch("claims").find { |entry| entry["id"] == CLAIM_ID }
        raise "missing comparative claim #{CLAIM_ID}" unless claim

        verify_claim_status!(registry, claim, status)
        verify_claim_evidence!(claim, records)
        verify_claim_limitations!(claim, status, records)
      end

      def verify_report_bindings!(root, status, records)
        REPORTS.each do |relative|
          path = ErrorUXReviewIdentity.repository_path(root, relative, "R001 public report")
          source = File.binread(path)
          block = marker_body(source, relative)
          raise "#{relative}: R001 status marker does not publish #{status}" unless block.include?("R001: `#{status}`")

          if status == "HOLD"
            verify_hold_report!(block, relative)
          else
            verify_pass_report!(source, block, relative, records)
          end
        end
      end

      def marker_body(source, relative)
        raise "#{relative}: R001 status markers must appear exactly once" unless
          source.scan(START_MARKER).length == 1 && source.scan(END_MARKER).length == 1

        body = source.split(START_MARKER, 2).last.split(END_MARKER, 2).first
        raise "#{relative}: R001 status marker is empty" if body.strip.empty?

        body
      end

      def verify_claim_status!(registry, claim, status)
        expected = status == "HOLD" ? %w[review_pending evidence pending] : %w[measured claim complete]
        actual = [claim.fetch("state"), claim.dig("binding", "kind"), claim.dig("subjective_review", "state")]
        raise "#{CLAIM_ID} state must be #{expected.join('/')} while R001 is #{status}" unless actual == expected

        verify_racc_comparison_state!(registry)
      end

      def verify_racc_comparison_state!(registry)
        racc = registry.fetch("comparison_set").find { |entry| entry["id"] == "racc" }
        raise "Racc comparison entry is missing" unless racc

        expected = ClaimStates.comparison_state("racc", registry.fetch("claims"))
        %w[state pending_claims reason].each do |key|
          next if racc.fetch(key) == expected.fetch(key)

          raise "Racc #{key} is stale; expected #{expected.fetch(key).inspect} from all registered claims"
        end
      end

      def verify_claim_evidence!(claim, records)
        evidence = claim.fetch("evidence").map { |entry| entry.fetch("path") }
        expected = CLAIM_EVIDENCE + records.map { |entry| entry.fetch("record_path") }
        missing = expected - evidence
        raise "#{CLAIM_ID} is missing R001 evidence: #{missing.join(', ')}" unless missing.empty?
      end

      def verify_claim_limitations!(claim, status, records)
        text = claim.fetch("limitations").join(" ")
        review_method = claim.dig("subjective_review", "method")
        if status == "HOLD"
          raise "#{CLAIM_ID} HOLD limitations must disclose missing independent review" unless
            text.include?("Independent subjective review is still missing")

          return
        end

        raise "#{CLAIM_ID} PASS limitations must retain the human-review limitation" unless
          claim.fetch("limitations").include?(HUMAN_LIMITATION)
        raise "#{CLAIM_ID} PASS review method must name every reviewer login" unless
          records.all? { |entry| review_method.downcase.include?(entry.fetch("publisher_github_login").downcase) }

        records.each do |entry|
          next if text.include?(entry.fetch("permalink")) && text.include?(entry.fetch("sha256"))

          raise "#{CLAIM_ID} PASS limitations must bind every review permalink and digest"
        end
      end

      def verify_hold_report!(block, relative)
        return if block.include?("awaiting_independent_review") &&
                  block.include?("error-ux-review-status-v1.json")

        raise "#{relative}: HOLD marker must link the awaiting R001 status"
      end

      def verify_pass_report!(source, block, relative, records)
        stale = STALE_PASS_TEXT.find { |text| source.downcase.include?(text) }
        raise "#{relative}: stale R001 HOLD text remains after PASS: #{stale}" if stale
        raise "#{relative}: PASS marker must not contain HOLD" if block.match?(/\bHOLD\b/)

        records.each do |entry|
          values = entry.values_at("record_path", "sha256", "permalink")
          missing = values.reject { |value| block.include?(value) }
          raise "#{relative}: PASS marker is missing record provenance #{missing.join(', ')}" unless missing.empty?
        end
      end
    end
  end
end
