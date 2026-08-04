# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "comparative_claims/publications"

module Ibex
  module Quality
    # Validates the comparative-claim registry and its public documentation bindings.
    class ComparativeClaims
      ROOT = File.expand_path("../..", __dir__)
      REGISTRY = File.join(ROOT, "docs/claims.yml")
      COMPARISON_SET = %w[racc lrama bison menhir tree_sitter antlr].freeze
      CLAIM_STATES = %w[measured review_pending not_compared].freeze
      TOOL_STATES = %w[compared not_compared].freeze
      UNKNOWN = %w[unknown not_applicable].freeze
      AGGREGATE_SCORE = /\b(?:aggregate|overall)\s+(?:score|ranking)\b|総合点/i
      CLAIM_KEYS = %w[
        id state title wording publication subjects public_command corpus environment
        unsupported_semantics subjective_review validity evidence limitations
      ].freeze

      def initialize(root: ROOT, registry: nil, readme: "README.md")
        @root = File.expand_path(root)
        @registry = registry || File.join(@root, "docs/claims.yml")
        @readme = readme
      end

      def verify!
        source = File.binread(@registry)
        reject_aggregate_score!(source, relative(@registry))
        document = load_yaml(source)
        exact_keys!(document, %w[schema_version comparison_set claims], "registry")
        raise "claim registry schema_version must be 1" unless document["schema_version"] == 1

        verify_comparison_set(document.fetch("comparison_set"))
        claims = document.fetch("claims")
        raise "claims must be a non-empty array" unless claims.is_a?(Array) && !claims.empty?

        ordered!(claims, "claims") { |claim| claim["id"] }
        claims.each { |claim| verify_claim(claim) }
        ClaimPublications.new(root: @root, claims: claims, readme: @readme).verify!
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

      def verify_comparison_set(tools)
        raise "comparison_set must be an array" unless tools.is_a?(Array)
        raise "comparison_set must use the canonical order" unless tools.map { |tool| tool["id"] } == COMPARISON_SET

        tools.each do |tool|
          exact_keys!(tool, %w[id name state version revision reason], "comparison_set entry")
          verify_tool_state(tool)
          non_empty_string!(tool.fetch("reason"), "#{tool.fetch('id')}: reason")
        end
      end

      def verify_tool_state(tool)
        id = tool.fetch("id")
        state = tool.fetch("state")
        raise "#{id}: invalid comparison state #{state.inspect}" unless TOOL_STATES.include?(state)

        values = [tool.fetch("version"), tool.fetch("revision")]
        if state == "not_compared"
          raise "#{id}: not_compared versions must be unknown" unless values == %w[unknown unknown]
        elsif values.include?("unknown")
          raise "#{id}: compared tools require an exact version or revision"
        end
      end

      def verify_claim(claim)
        exact_keys!(claim, CLAIM_KEYS, "claim")
        id = claim.fetch("id")
        raise "invalid claim id #{id.inspect}" unless id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
        raise "#{id}: invalid state" unless CLAIM_STATES.include?(claim.fetch("state"))

        %w[title wording].each { |key| non_empty_string!(claim.fetch(key), "#{id}: #{key}") }
        verify_publication_record(id, claim.fetch("publication"))
        verify_subjects(id, claim.fetch("subjects"), claim.fetch("state"))
        string_array!(claim.fetch("public_command"), "#{id}: public_command")
        record_array!(claim.fetch("corpus"), %w[id path revision], "#{id}: corpus", order_key: "id")
        verify_environment(id, claim.fetch("environment"))
        string_array!(claim.fetch("unsupported_semantics"), "#{id}: unsupported_semantics")
        verify_review(id, claim.fetch("subjective_review"), claim.fetch("state"))
        verify_validity(id, claim.fetch("validity"))
        verify_evidence(id, claim.fetch("evidence"))
        string_array!(claim.fetch("limitations"), "#{id}: limitations")
      end

      def verify_publication_record(id, publication)
        exact_keys!(publication, %w[path marker], "#{id}: publication")
        non_empty_string!(publication.fetch("path"), "#{id}: publication path")
        raise "#{id}: publication marker must equal the claim id" unless publication.fetch("marker") == id
      end

      def verify_subjects(id, subjects, state)
        record_array!(subjects, %w[tool version revision], "#{id}: subjects", order_key: "tool")
        tools = subjects.map { |subject| subject.fetch("tool") }
        raise "#{id}: subjects must include Ibex and a comparison tool" unless
          tools.include?("ibex") && (tools & COMPARISON_SET).any?
        return if state == "not_compared"

        subjects.each do |subject|
          values = subject.values_at("version", "revision")
          raise "#{id}: measured subjects require exact identities" if values.include?("unknown")
        end
      end

      def verify_environment(id, environment)
        exact_keys!(environment, %w[known unknown], "#{id}: environment")
        known = environment.fetch("known")
        raise "#{id}: environment known values must be a non-empty mapping" unless known.is_a?(Hash) && !known.empty?

        known.each { |key, value| non_empty_string!(value, "#{id}: environment #{key}") }
        unknown = environment.fetch("unknown")
        raise "#{id}: environment unknown must be an array" unless unknown.is_a?(Array)

        string_array!(unknown, "#{id}: environment unknown", allow_empty: true)
        ordered_values!(unknown, "#{id}: environment unknown")
      end

      def verify_review(id, review, state)
        exact_keys!(review, %w[required state method], "#{id}: subjective_review")
        unless [true, false].include?(review.fetch("required"))
          raise "#{id}: subjective_review required must be boolean"
        end

        %w[state method].each { |key| non_empty_string!(review.fetch(key), "#{id}: review #{key}") }
        return unless state == "review_pending"

        raise "#{id}: review_pending requires a pending subjective review" unless
          review.fetch("required") && review.fetch("state") == "pending"
      end

      def verify_validity(id, validity)
        exact_keys!(validity, %w[scope expires review_when], "#{id}: validity")
        %w[scope expires].each { |key| non_empty_string!(validity.fetch(key), "#{id}: validity #{key}") }
        string_array!(validity.fetch("review_when"), "#{id}: validity review_when")
      end

      def verify_evidence(id, evidence)
        record_array!(evidence, %w[path description], "#{id}: evidence", order_key: "path")
        evidence.each do |entry|
          path = repository_path(entry.fetch("path"), "#{id}: evidence")
          raise "#{id}: missing evidence #{entry.fetch('path')}" unless File.file?(path)
        end
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
        ordered_values!(values, label)
      end

      def ordered_values!(values, label)
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

      def reject_aggregate_score!(source, path)
        raise "#{path}: aggregate scores and rankings are forbidden" if source.match?(AGGREGATE_SCORE)
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end
  end
end
