# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

module Ibex
  module Quality
    module ErrorUXReviewIdentity
      CASE_IDS = (1..10).map { |number| format("EUX-%02d", number) }.freeze
      SHA256 = /\A[0-9a-f]{64}\z/
      REVISION = /\A[0-9a-f]{40}\z/
      PLACEHOLDER = /(?:REPLACE_WITH|\bTBD\b|\bTODO\b)/i
      PUBLIC_LINKS = {
        "README.md" => ["(docs/error-ux-review-status-v1.json)"],
        "docs/error-ux.md" => [
          "(error-ux-review-status-v1.json)", "(error-ux-review-rubric-v1.md)",
          "(../schema/error-ux-review-v1.schema.json)"
        ],
        "docs/release-readiness.md" => [
          "(error-ux-review-status-v1.json)", "(error-ux-review-rubric-v1.md)"
        ],
        "docs/error-ux-reviews/v1/records/README.md" => [
          "(../../../error-ux-review-status-v1.json)", "(../../../error-ux-review-rubric-v1.md)"
        ]
      }.freeze
      CLAIM_ID = "racc-error-ux-json-v1"
      CLAIM_EVIDENCE = %w[
        docs/error-ux-review-rubric-v1.md docs/error-ux-review-status-v1.json
        schema/error-ux-review-v1.schema.json
      ].freeze

      module_function

      def digest(value)
        Digest::SHA256.hexdigest(value)
      end

      def file_digest(path)
        digest(File.binread(path))
      end

      def exact_keys!(record, expected, label)
        raise "#{label} must be an object" unless record.is_a?(Hash)
        return if record.keys.sort == expected.sort

        raise "#{label} keys must be #{expected.sort.join(', ')}"
      end

      def repository_path(root, relative, label)
        raise "#{label} must be a relative path" unless relative.is_a?(String) && !relative.strip.empty?
        raise "#{label} must be relative" if Pathname.new(relative).absolute?

        absolute = File.expand_path(relative, root)
        raise "#{label} escapes the repository" unless absolute.start_with?("#{root}/")

        absolute
      end

      def git_show(root, revision, relative)
        raise "repository revision must be a full 40-hex SHA" unless revision.match?(REVISION)

        repository_path(root, relative, "git object path")
        output, error, status = Open3.capture3("git", "-C", root, "show", "#{revision}:#{relative}")
        raise "cannot read #{relative} at #{revision}: #{error.strip}" unless status.success?

        output
      end

      def git_revision(root)
        output, error, status = Open3.capture3("git", "-C", root, "rev-parse", "HEAD")
        raise "cannot resolve repository revision: #{error.strip}" unless status.success?

        revision = output.strip
        raise "repository revision must be a full 40-hex SHA" unless revision.match?(REVISION)

        revision
      end

      def parse_json(path, label)
        JSON.parse(File.binread(path))
      rescue JSON::ParserError => e
        raise "#{label} is invalid JSON: #{e.message}"
      end

      def placeholder?(value)
        case value
        when Hash then value.any? { |key, child| placeholder?(key) || placeholder?(child) }
        when Array then value.any? { |child| placeholder?(child) }
        when String then value.match?(PLACEHOLDER)
        else false
        end
      end

      def verify_public_links!(root)
        PUBLIC_LINKS.each do |relative, links|
          path = repository_path(root, relative, "public review document")
          raise "missing public review document #{relative}" unless File.file?(path)

          source = File.binread(path)
          missing = links.reject { |link| source.include?(link) }
          raise "#{relative}: missing review links #{missing.join(', ')}" unless missing.empty?
        end
      end

      def verify_claim_state!(root, status)
        path = repository_path(root, "docs/claims.yml", "comparative claim registry")
        registry = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
        claim = registry.fetch("claims").find { |entry| entry["id"] == CLAIM_ID }
        raise "missing comparative claim #{CLAIM_ID}" unless claim

        expected = status == "HOLD" ? %w[review_pending evidence pending] : %w[measured claim complete]
        actual = [claim.fetch("state"), claim.dig("binding", "kind"), claim.dig("subjective_review", "state")]
        raise "#{CLAIM_ID} state must be #{expected.join('/')} while R001 is #{status}" unless actual == expected

        evidence = claim.fetch("evidence").map { |entry| entry.fetch("path") }
        missing = CLAIM_EVIDENCE - evidence
        raise "#{CLAIM_ID} is missing R001 evidence: #{missing.join(', ')}" unless missing.empty?
      end
    end
  end
end
