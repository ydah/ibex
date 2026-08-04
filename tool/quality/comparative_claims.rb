# frozen_string_literal: true

require "pathname"
require "shellwords"
require "yaml"
require_relative "comparative_claims/identities"
require_relative "comparative_claims/publications"
require_relative "comparative_claims/wording"

module Ibex
  module Quality
    # Validates comparative records, evidence, and public documentation bindings.
    class ComparativeClaims
      ROOT = File.expand_path("../..", __dir__)
      COMPARISON_SET = %w[racc lrama bison menhir tree_sitter antlr].freeze
      CLAIM_STATES = %w[evidence_pending measured review_pending].freeze
      CLAIM_KEYS = %w[
        id state title wording binding subjects public_command corpus environment
        unsupported_semantics subjective_review validity evidence limitations missing_evidence
      ].freeze

      def initialize(root: ROOT, registry: nil, readme: "README.md")
        @root = File.expand_path(root)
        @registry = registry || File.join(@root, "docs/claims.yml")
        @readme = readme
      end

      def verify!
        source = File.read(@registry, encoding: Encoding::UTF_8)
        ComparativeWording.verify!(source, path: relative(@registry))
        document = load_yaml(source)
        exact_keys!(document, %w[schema_version comparison_set claims], "registry")
        raise "claim registry schema_version must be 1" unless document["schema_version"] == 1

        tools = document.fetch("comparison_set")
        ClaimIdentities.verify_comparison_set_order!(tools, COMPARISON_SET)
        claims = document.fetch("claims")
        raise "claims must be a non-empty array" unless claims.is_a?(Array) && !claims.empty?

        ordered!(claims, "claims") { |claim| claim["id"] }
        claims.each { |claim| verify_claim(claim) }
        ClaimIdentities.verify_comparison_set!(tools, COMPARISON_SET, claims)
        aliases = tools.to_h { |tool| [tool.fetch("id"), tool.fetch("aliases")] }
        ClaimPublications.new(root: @root, claims: claims, readme: @readme, aliases: aliases).verify!
        true
      rescue KeyError => e
        raise "invalid comparative claim registry: #{e.message}"
      end

      private

      def load_yaml(source)
        document = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
        raise "claim registry root must be a mapping" unless document.is_a?(Hash)

        document
      rescue Psych::Exception => e
        raise "claim registry YAML is invalid: #{e.message}"
      end

      def verify_claim(claim)
        exact_keys!(claim, CLAIM_KEYS, "claim")
        id = claim.fetch("id")
        raise "invalid claim id #{id.inspect}" unless id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
        raise "#{id}: invalid state" unless CLAIM_STATES.include?(claim.fetch("state"))

        %w[title wording].each { |key| non_empty_string!(claim.fetch(key), "#{id}: #{key}") }
        verify_binding(id, claim.fetch("binding"))
        ClaimIdentities.verify_subjects!(id, claim.fetch("subjects"), COMPARISON_SET)
        verify_execution_context(id, claim)
        verify_claim_evidence(id, claim)
      end

      def verify_execution_context(id, claim)
        verify_command(id, claim.fetch("public_command"))
        corpus = claim.fetch("corpus")
        ClaimIdentities.verify_corpus!(id, corpus)
        corpus.each do |entry|
          path = repository_path(entry.fetch("path"), "#{id}: corpus")
          raise "#{id}: missing corpus #{entry.fetch('path')}" unless File.file?(path)
        end
        ClaimIdentities.verify_environment!(
          id, claim.fetch("environment"), claim.fetch("limitations"), wording: claim.fetch("wording")
        )
      end

      def verify_claim_evidence(id, claim)
        string_array!(claim.fetch("unsupported_semantics"), "#{id}: unsupported_semantics")
        verify_validity(id, claim.fetch("validity"))
        evidence = verify_evidence(id, claim.fetch("evidence"))
        string_array!(claim.fetch("limitations"), "#{id}: limitations")
        missing = claim.fetch("missing_evidence")
        string_array!(missing, "#{id}: missing_evidence", allow_empty: true)
        verify_state!(claim, evidence, missing)
      end

      def verify_binding(id, binding)
        exact_keys!(binding, %w[path marker kind required_text allowed_strength body_sha256], "#{id}: binding")
        non_empty_string!(binding.fetch("path"), "#{id}: binding path")
        raise "#{id}: binding marker must equal the claim id" unless binding.fetch("marker") == id
        raise "#{id}: binding kind must be claim or evidence" unless %w[claim evidence].include?(binding.fetch("kind"))

        string_array!(binding.fetch("required_text"), "#{id}: binding required_text")
        string_array!(binding.fetch("allowed_strength"), "#{id}: binding allowed_strength", allow_empty: true)
        raise "#{id}: binding body_sha256 must be 64 lowercase hex" unless
          binding.fetch("body_sha256").match?(/\A[0-9a-f]{64}\z/)
      end

      def verify_command(id, command)
        exact_keys!(command, %w[executable argv], "#{id}: public_command")
        executable = command.fetch("executable")
        non_empty_string!(executable, "#{id}: command executable")
        raise "#{id}: command executable must be one argv token" if executable.match?(/[\s\0]/)

        argv = command.fetch("argv")
        string_array!(argv, "#{id}: command argv")
        raise "#{id}: command argv cannot contain NUL" if argv.any? { |argument| argument.include?("\0") }

        tokens = [executable, *argv]
        rendered = Shellwords.join(tokens)
        raise "#{id}: command cannot be reconstructed losslessly" unless Shellwords.split(rendered) == tokens
      end

      def verify_validity(id, validity)
        exact_keys!(validity, %w[scope expires review_when], "#{id}: validity")
        %w[scope expires].each { |key| non_empty_string!(validity.fetch(key), "#{id}: validity #{key}") }
        string_array!(validity.fetch("review_when"), "#{id}: validity review_when")
      end

      def verify_evidence(id, evidence)
        record_array!(evidence, %w[kind path description], "#{id}: evidence", order_key: "path")
        evidence.each do |entry|
          unless %w[corpus method report result_artifact].include?(entry.fetch("kind"))
            raise "#{id}: invalid evidence kind"
          end

          path = repository_path(entry.fetch("path"), "#{id}: evidence")
          raise "#{id}: missing evidence #{entry.fetch('path')}" unless File.file?(path)
        end
        evidence
      end

      def verify_state!(claim, evidence, missing)
        id = claim.fetch("id")
        state = claim.fetch("state")
        binding_kind = claim.dig("binding", "kind")
        review = claim.fetch("subjective_review")
        exact_keys!(review, %w[required state method], "#{id}: subjective_review")
        unless [true, false].include?(review.fetch("required"))
          raise "#{id}: subjective_review required must be boolean"
        end

        %w[state method].each { |key| non_empty_string!(review.fetch(key), "#{id}: review #{key}") }
        case state
        when "measured" then verify_measured_state!(id, binding_kind, review, evidence, missing)
        when "review_pending" then verify_review_pending_state!(id, binding_kind, review, evidence, missing)
        when "evidence_pending" then verify_evidence_pending_state!(id, binding_kind, review, missing)
        end
      end

      def verify_measured_state!(id, binding_kind, review, evidence, missing)
        raise "#{id}: measured claims require a public claim binding" unless binding_kind == "claim"
        raise "#{id}: measured claims cannot have missing evidence" unless missing.empty?
        raise "#{id}: measured claims require a result artifact" unless result_artifact?(evidence)
        return if review.fetch("required") && review.fetch("state") == "complete"
        return if !review.fetch("required") && review.fetch("state") == "not_applicable"

        raise "#{id}: measured claim has an invalid subjective review state"
      end

      def verify_review_pending_state!(id, binding_kind, review, evidence, missing)
        raise "#{id}: pending claims require an evidence binding" unless binding_kind == "evidence"
        raise "#{id}: review_pending must not have missing evidence" unless missing.empty?
        raise "#{id}: review_pending requires a result artifact" unless result_artifact?(evidence)
        return if review.fetch("required") && review.fetch("state") == "pending"

        raise "#{id}: review_pending requires a pending subjective review"
      end

      def verify_evidence_pending_state!(id, binding_kind, review, missing)
        raise "#{id}: pending claims require an evidence binding" unless binding_kind == "evidence"
        raise "#{id}: evidence_pending must name missing evidence" if missing.empty?
        return if !review.fetch("required") && review.fetch("state") == "not_applicable"

        raise "#{id}: evidence_pending has an invalid subjective review state"
      end

      def result_artifact?(evidence)
        evidence.any? { |entry| entry["kind"] == "result_artifact" }
      end

      def record_array!(records, keys, label, order_key:)
        raise "#{label} must be a non-empty array" unless records.is_a?(Array) && !records.empty?

        ordered!(records, label) { |record| record[order_key] }
        records.each do |record|
          exact_keys!(record, keys, label)
          keys.each { |key| non_empty_string!(record.fetch(key), "#{label} #{key}") }
        end
      end

      def string_array!(values, label, allow_empty: false)
        valid_size = allow_empty || !values.empty? if values.is_a?(Array)
        raise "#{label} must be #{allow_empty ? 'an' : 'a non-empty'} array of strings" unless valid_size

        values.each { |value| non_empty_string!(value, label) }
      end

      def ordered!(records, label, &key)
        values = records.map(&key)
        raise "#{label} must be ordered deterministically" unless values == values.sort && values.uniq == values
      end

      def exact_keys!(record, expected, label)
        raise "#{label} must be a mapping" unless record.is_a?(Hash)
        raise "#{label} keys must be #{expected.sort.join(', ')}" unless record.keys.sort == expected.sort
      end

      def non_empty_string!(value, label)
        raise "#{label} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
      end

      def repository_path(path, label)
        non_empty_string!(path, label)
        raise "#{label} path must be relative" if Pathname.new(path).absolute?

        absolute = File.expand_path(path, @root)
        raise "#{label} path escapes the repository" unless absolute.start_with?("#{@root}/")

        absolute
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end
  end
end
