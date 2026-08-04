# frozen_string_literal: true

module Ibex
  module Quality
    # Exact identity and environment rules for reproducible comparative records.
    module ClaimIdentities
      REVISION = /\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/
      VERSION = /\A\d+\.\d+\.\d+(?:[.-][0-9A-Za-z.-]+)?\z/
      PLACEHOLDER = %r{\A(?:unknown|tbd|todo|n/a|<.*>|/path/to(?:/|\z))}i
      ENVIRONMENT_FIELDS = %w[
        cpu_model host_cpu host_os kernel_release processors ruby_engine ruby_platform ruby_version yjit_enabled
      ].freeze
      TOOL_STATES = %w[compared evidence_pending not_compared].freeze
      COMPARISON_ALIASES = {
        "racc" => ["Racc"],
        "lrama" => ["Lrama"],
        "bison" => ["GNU Bison", "Bison", "GNU yacc", "yacc"],
        "menhir" => ["Menhir"],
        "tree_sitter" => ["Tree-sitter", "Tree sitter", "tree_sitter"],
        "antlr" => %w[ANTLR ANTLR4]
      }.freeze

      module_function

      def exact_version!(value, label)
        raise "#{label} must be an exact release version" unless value.is_a?(String) && value.match?(VERSION)
      end

      def exact_revision!(value, label)
        return if value.is_a?(String) && value.match?(REVISION)

        raise "#{label} must be an immutable 40- or 64-hex revision"
      end

      def verify_comparison_set!(tools, order)
        raise "comparison_set must be an array" unless tools.is_a?(Array)
        raise "comparison_set must use the canonical order" unless tools.map { |tool| tool["id"] } == order

        tools.each { |tool| verify_comparison_tool!(tool) }
      end

      def verify_comparison_tool!(tool)
        exact_keys!(tool, %w[id name state version revision reason aliases], "comparison_set entry")
        state = tool.fetch("state")
        raise "#{tool.fetch('id')}: invalid comparison state #{state.inspect}" unless TOOL_STATES.include?(state)

        verify_comparison_tool_identity!(tool, state)
        expected = COMPARISON_ALIASES.fetch(tool.fetch("id"))
        raise "#{tool.fetch('id')}: aliases must match the canonical list" unless tool.fetch("aliases") == expected
      end

      def verify_comparison_tool_identity!(tool, state)
        values = tool.values_at("version", "revision")
        if state == "not_compared"
          raise "#{tool.fetch('id')}: not_compared identity must be unknown" unless values == %w[unknown unknown]
        else
          exact_version!(tool.fetch("version"), "#{tool.fetch('id')}: version")
          raise "#{tool.fetch('id')}: release revision must be not_applicable" unless
            tool.fetch("revision") == "not_applicable"
        end
      end

      def verify_subjects!(id, subjects, comparison_set)
        records!(subjects, %w[tool identity_kind version revision], "#{id}: subjects", "tool")
        tools = subjects.map { |subject| subject.fetch("tool") }
        raise "#{id}: subjects must include Ibex and a comparison tool" unless
          tools.include?("ibex") && (tools & comparison_set).any?

        unknown = tools - ["ibex"] - comparison_set
        raise "#{id}: unknown comparison subjects: #{unknown.join(', ')}" unless unknown.empty?

        subjects.each { |subject| verify_subject!(id, subject) }
      end

      def verify_subject!(id, subject)
        tool = subject.fetch("tool")
        kind = subject.fetch("identity_kind")
        exact_version!(subject.fetch("version"), "#{id}: #{tool} version")
        if kind == "repository"
          exact_revision!(subject.fetch("revision"), "#{id}: #{tool} revision")
        elsif kind == "release"
          raise "#{id}: #{tool} release revision must be not_applicable" unless
            subject.fetch("revision") == "not_applicable"
        else
          raise "#{id}: #{tool} identity_kind must be repository or release"
        end
        raise "#{id}: Ibex identity must be repository-bound" if tool == "ibex" && kind != "repository"
      end

      def verify_corpus!(id, corpus)
        records!(corpus, %w[id path revision], "#{id}: corpus", "id")
        corpus.each { |entry| exact_revision!(entry.fetch("revision"), "#{id}: corpus #{entry.fetch('id')}") }
      end

      def verify_environment!(id, environment, limitations, wording:)
        exact_keys!(environment, %w[known unknown], "#{id}: environment")
        known = environment.fetch("known")
        unknown = environment.fetch("unknown")
        verify_environment_shape!(id, known, unknown)

        known.each do |key, value|
          verify_environment_value!(id, key, value)
          verify_environment_scope!(id, key, value, wording)
        end
        verify_environment_coverage!(id, known, unknown, limitations)
      end

      def verify_environment_shape!(id, known, unknown)
        raise "#{id}: environment known values must be a mapping" unless known.is_a?(Hash)
        raise "#{id}: environment unknown must be an array" unless unknown.is_a?(Array)
        raise "#{id}: environment known keys must be ordered" unless known.keys == known.keys.sort

        return if unknown == unknown.sort && unknown.uniq == unknown

        raise "#{id}: environment unknown must be ordered and unique"
      end

      def verify_environment_coverage!(id, known, unknown, limitations)
        missing = ENVIRONMENT_FIELDS - known.keys - unknown
        raise "#{id}: environment identity fields are missing: #{missing.join(', ')}" unless missing.empty?

        raise "#{id}: environment fields cannot be both known and unknown" unless (known.keys & unknown).empty?

        limitations_text = Array(limitations).join(" ")
        unpublished = unknown.reject { |key| limitations_text.include?(key) }
        return if unpublished.empty?

        raise "#{id}: unknown environment fields must be published in limitations: #{unpublished.join(', ')}"
      end

      def verify_environment_value!(id, key, value)
        raise "#{id}: environment #{key} must be a non-placeholder scalar" unless
          value.is_a?(String) && !value.strip.empty? && !value.match?(PLACEHOLDER) && !value.include?("\0")
        raise "#{id}: yjit_enabled must be true or false" if key == "yjit_enabled" && !%w[true false].include?(value)
        raise "#{id}: processors must be a positive integer" if key == "processors" && !value.match?(/\A[1-9]\d*\z/)
      end

      def verify_environment_scope!(id, key, value, wording)
        expected = if key == "yjit_enabled"
                     value == "false" ? "yjit disabled" : "yjit enabled"
                   else
                     value
                   end
        return if wording.downcase.include?(expected.downcase)

        raise "#{id}: known environment #{key}=#{value} must appear in scoped wording"
      end

      def records!(records, keys, label, order_key)
        raise "#{label} must be a non-empty array" unless records.is_a?(Array) && !records.empty?
        raise "#{label} must be ordered deterministically" unless
          records.map { |record| record[order_key] }.then { |values| values == values.sort && values.uniq == values }

        records.each do |record|
          exact_keys!(record, keys, label)
          keys.each do |key|
            value = record.fetch(key)
            raise "#{label} #{key} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
          end
        end
      end

      def exact_keys!(record, expected, label)
        raise "#{label} must be a mapping" unless record.is_a?(Hash)
        raise "#{label} keys must be #{expected.sort.join(', ')}" unless record.keys.sort == expected.sort
      end
    end
  end
end
