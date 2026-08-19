# frozen_string_literal: true

require "digest"
require "json"
require "open3"

module Ibex
  module Quality
    # Verifies the reviewed history and byte identity behind the I001 dossier.
    # The dossier remains the semantic source of truth; this class only checks
    # that its published evidence was not silently replaced.
    class DirectIELRProvenance
      DOSSIER_REVISION = "94ee6dfe1dd73e2d89b729786b1200799bf1d2e9"
      DOSSIER_PATH = "tool/quality/evidence/direct-ielr-decision-v1.json"
      DOSSIER_DIGEST = "bbe89c714f12c44e2e857554492b28d778ff7b6808cfe0eaa8d82192752dec59"
      DECISION_REVISION = "5c569ceaf06e9fb217ea5211194d605bbbc3e2ff"
      DECISION_DATE = "2026-08-19"
      DECISION_REVISION_ROLE = "reviewed repository evidence immediately before dossier publication"
      V001_REVISION = "f9d2c54eb4b27fc5ffe798bb0b29d038d97ee35c"
      V001_PARENT_REVISION = "8a6c08259dd2a5dbb5c1d5330f06cbdffcf4c940"
      SOURCE_IDS = %w[
        h005-human-report h005-machine-evidence h005-evidence-schema
        v001-trust-boundary v001-reference-collection v001-verifier
      ].freeze
      V001_SOURCE_DIGESTS = {
        "docs/verifier-trust-boundary.md" => "12568cd0e22a291a3d1466e537c32062fc490fd4bcb6bc886971b78f1aefbe46",
        "lib/ibex/verify/reference_collection.rb" => "d07e900652c61ddd942380d49edce0a3c811605cd82490c1e0e6db54010746fb",
        "lib/ibex/verify/verifier.rb" => "66efb73edf90d5466e102ea756c5b36e645ea6f5a780250b0b056dbfe34a80a3"
      }.freeze

      def initialize(root:, dossier:)
        @root = File.expand_path(root)
        @dossier = dossier
      end

      def verify_repository_history!
        validate_repository_history!
      end

      def verify!(document, profile)
        validate_repository_history!
        decision = document.fetch("decision")
        raise "decision date identity drift" unless decision.fetch("date") == DECISION_DATE
        raise "decision revision identity drift" unless decision.fetch("revision") == DECISION_REVISION
        raise "decision revision role drift" unless decision.fetch("revision_role") == DECISION_REVISION_ROLE
        decision_revision = document.dig("decision", "revision")
        verify_revision!(decision_revision, "decision")
        verify_dossier_parent!(decision_revision)
        verify_h005_identity!(document, profile)
        verify_v001_identity!(document)
        verify_sources!(document, decision_revision)
        validate_dossier_identity!
      end

      private

      def verify_h005_identity!(document, profile)
        provenance = profile.fetch("provenance")
        identity = document.fetch("evidence_identity")
        {
          "profile_capture_base_revision" => "base_revision",
          "profile_bound_paths_sha256" => "bound_paths_sha256",
          "profile_implementation_sha256" => "implementation_sha256"
        }.each do |dossier_field, profile_field|
          next if identity.fetch(dossier_field) == provenance.fetch(profile_field)

          raise "H005 #{dossier_field} identity drift"
        end
      end

      def verify_v001_identity!(document)
        identity = document.fetch("evidence_identity")
        v001_revision = identity.fetch("v001_revision")
        raise "V001 revision identity drift" unless v001_revision == V001_REVISION

        verify_revision!(v001_revision, "V001", ancestor_of: DECISION_REVISION)
        parent, status = capture("git", "rev-parse", "#{V001_REVISION}^")
        raise "V001 parent revision is unavailable" unless status.success?
        raise "V001 parent revision identity drift" unless parent.strip == V001_PARENT_REVISION

        _output, status = capture("git", "cat-file", "-e", "#{V001_PARENT_REVISION}^{commit}")
        raise "V001 parent commit object is unavailable" unless status.success?

        V001_SOURCE_DIGESTS.each do |path, digest|
          bytes, status = capture("git", "show", "#{V001_REVISION}:#{path}")
          raise "V001 source is unavailable at the bound revision: #{path}" unless status.success?
          raise "V001 source identity drift at the bound revision: #{path}" unless
            Digest::SHA256.hexdigest(bytes.b) == digest
        end

        _bytes, status = capture("git", "show", "#{V001_PARENT_REVISION}:docs/verifier-trust-boundary.md")
        raise "V001 trust-boundary source was not introduced at the bound revision" if status.success?
      end

      def verify_sources!(document, decision_revision)
        sources = document.dig("evidence_identity", "sources")
        source_ids = sources.map { |source| source.fetch("id") }
        raise "direct IELR evidence source inventory drift" unless source_ids == SOURCE_IDS
        raise "direct IELR evidence source IDs are duplicated" unless source_ids.uniq == source_ids

        sources.each { |source| verify_source!(decision_revision, source) }
        digest = Digest::SHA256.hexdigest(JSON.generate(sources))
        expected = document.dig("evidence_identity", "sources_sha256")
        raise "direct IELR evidence source digest drift" unless digest == expected
      end

      def verify_dossier_parent!(decision_revision)
        verify_revision!(DOSSIER_REVISION, "dossier")
        _output, status = capture("git", "merge-base", "--is-ancestor", decision_revision, DOSSIER_REVISION)
        raise "decision revision is not an ancestor of the dossier revision" unless status.success?
      end

      def validate_repository_history!
        shallow, status = capture("git", "rev-parse", "--is-shallow-repository")
        raise "repository history state is unavailable" unless status.success?
        raise "direct IELR decision requires full Git history" unless shallow.strip == "false"
      end

      def validate_dossier_identity!
        source = File.binread(@dossier)
        raise "direct IELR decision dossier digest drift" unless Digest::SHA256.hexdigest(source) == DOSSIER_DIGEST

        bytes, status = capture("git", "show", "#{DOSSIER_REVISION}:#{DOSSIER_PATH}")
        raise "direct IELR decision dossier is unavailable at its publication revision" unless status.success?
        raise "direct IELR decision dossier publication digest drift" unless
          Digest::SHA256.hexdigest(bytes.b) == DOSSIER_DIGEST
      end

      def verify_revision!(revision, label, ancestor_of: "HEAD")
        _output, status = capture("git", "cat-file", "-e", "#{revision}^{commit}")
        raise "#{label} revision is unavailable" unless status.success?

        _output, status = capture("git", "merge-base", "--is-ancestor", revision, ancestor_of)
        raise "#{label} revision is not in the reviewed history" unless status.success?
      end

      def verify_source!(revision, source)
        path = source.fetch("path")
        expected = source.fetch("sha256")
        current = File.join(@root, path)
        raise "decision evidence source is unavailable: #{path}" unless File.file?(current)
        raise "decision evidence source digest drift: #{path}" unless Digest::SHA256.file(current).hexdigest == expected

        bytes, status = capture("git", "show", "#{revision}:#{path}")
        raise "decision evidence source is unavailable at reviewed revision: #{path}" unless status.success?
        return if Digest::SHA256.hexdigest(bytes.b) == expected

        raise "decision evidence source digest drift at reviewed revision: #{path}"
      end

      def capture(*command)
        stdout, _stderr, status = Open3.capture3(*command, chdir: @root)
        [stdout, status]
      end
    end
  end
end
