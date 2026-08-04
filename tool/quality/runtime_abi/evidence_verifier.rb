# frozen_string_literal: true

module Ibex
  module Quality
    # Binds behavioral ABI policy statements to executable regression evidence.
    class RuntimeABIEvidenceVerifier
      def initialize(root:)
        @root = File.expand_path(root)
      end

      def verify!
        require_fragments(
          "lib/ibex/ir/migration.rb",
          "value.schema_version == 1 && to == 2", "return value if value.schema_version == to"
        )
        require_fragments(
          "test/ir/golden_fixture_test.rb",
          "test_schema_v1_golden_fixtures_remain_byte_stable",
          "test_schema_v1_to_v2_migration_golden_fixtures",
          "test_automaton_migration_upgrades_embedded_grammar_and_recalculates_digest"
        )
        require_fragments(
          "test/ir/lexer_ir_test.rb",
          "test_normalizes_and_round_trips_an_independently_versioned_lexer",
          "test_embeds_the_lexer_without_changing_its_schema_version"
        )
        verify_runtime_evidence
      end

      private

      def verify_runtime_evidence
        require_fragments(
          "lib/ibex/runtime/parser.rb",
          "SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS.include?(actual)",
          "actual == PARSER_TABLE_FORMAT_VERSION && cst.is_a?(Hash)"
        )
        require_fragments(
          "test/runtime/table_format_test.rb",
          "test_version_one_through_five_tables_remain_accepted",
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
    end
  end
end
