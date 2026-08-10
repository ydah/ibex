# frozen_string_literal: true

require "yaml"
require_relative "reviewed_policy"

module Ibex
  module Quality
    # Binds behavioral ABI policy statements to executable regression evidence.
    class RuntimeABIEvidenceVerifier
      def initialize(root:)
        @root = File.expand_path(root)
      end

      def verify!
        require_fragments(
          "test/ir/golden_fixture_test.rb",
          "test_current_ir_rejects_explicitly_old_versions",
          "test_current_automaton_ir_golden_fixture"
        )
        require_fragments(
          "test/ir/lexer_ir_test.rb",
          "test_normalizes_and_round_trips_an_independently_versioned_lexer",
          "test_embeds_the_lexer_without_changing_the_grammar_format"
        )
        verify_runtime_evidence
        verify_pull_request_template
      end

      private

      def verify_runtime_evidence
        require_fragments(
          "lib/ibex/runtime/parser.rb",
          "SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS.include?(actual)",
          "return if cst.is_a?(Hash)"
        )
        require_fragments(
          "test/runtime/table_format_test.rb",
          "test_previous_table_formats_fail_before_reading_tokens",
          "test_legacy_cst_tables_fail_before_reading_tokens",
          "test_unsupported_parser_table_format_version_fails_before_reading_tokens"
        )
        require_fragments(
          "test/packaging/runtime_gem_test.rb",
          "test_nonembedded_generated_parser_runs_with_runtime_files_only",
          "test_embedded_generated_parser_remains_dependency_free"
        )
      end

      def require_fragments(relative_path, *fragments)
        source = File.binread(File.join(@root, relative_path))
        missing = fragments.reject { |fragment| source.include?(fragment) }
        raise "#{relative_path} is missing ABI evidence: #{missing.join(', ')}" unless missing.empty?
      end

      def verify_pull_request_template
        source = File.binread(File.join(@root, ".github/pull_request_template.md"))
        start_marker = "<!-- ibex-runtime-abi-assessment:start -->"
        end_marker = "<!-- ibex-runtime-abi-assessment:end -->"
        unless source.scan(start_marker).length == 1 && source.scan(end_marker).length == 1
          raise "pull request template must contain one complete ABI assessment"
        end

        pattern = /#{Regexp.escape(start_marker)}\s*```yaml\s*\n(.*?)```\s*#{Regexp.escape(end_marker)}/m
        matches = source.scan(pattern)
        raise "pull request template must contain one ABI assessment" unless matches.length == 1

        value = YAML.safe_load(matches.fetch(0).fetch(0), permitted_classes: [], aliases: false)
        required = RuntimeABIReviewedPolicy::ASSESSMENT.fetch("required_fields")
        raise "pull request template ABI fields are stale" unless value.is_a?(Hash) && value.keys.sort == required.sort
        unless value.fetch("rationale") == RuntimeABIReviewedPolicy::RATIONALE_SENTINEL
          raise "pull request template rationale sentinel is stale"
        end
      rescue Psych::Exception => e
        raise "pull request template ABI assessment is invalid YAML: #{e.message}"
      end
    end
  end
end
