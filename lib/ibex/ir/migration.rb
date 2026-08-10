# frozen_string_literal: true

require_relative "migration_metadata"

module Ibex
  module IR
    # Meaning-preserving upgrades between published IR schema versions.
    module Migration
      # @rbs skip
      UNAVAILABLE_V2_CONFIGURATION = MigrationMetadata::UNAVAILABLE_V2_CONFIGURATION

      # @rbs (Grammar | Automaton value, ?to: Integer) -> (Grammar | Automaton)
      def to_version(value, to: SCHEMA_VERSION)
        return value if value.schema_version == to
        return to_v3(value) if value.schema_version == 2 && to == 3

        raise Ibex::Error,
              "(ir):1:1: cannot migrate schema_version #{value.schema_version} to #{to}; " \
              "supported upgrade is 2 to 3"
      end
      module_function :to_version

      # @rbs skip
      def to_v3(value)
        return value if value.schema_version == 3
        unless value.schema_version == 2
          raise Ibex::Error, "(ir):1:1: cannot migrate unsupported schema_version #{value.schema_version}"
        end

        return migrate_grammar_to_v3(value) if value.is_a?(Grammar)
        return migrate_automaton_to_v3(value) if value.is_a?(Automaton)

        raise Ibex::Error, "(ir):1:1: cannot migrate unsupported IR object #{value.class}"
      end
      module_function :to_v3

      # @rbs skip
      def migrate_grammar_to_v3(grammar)
        Grammar.v3(
          class_name: grammar.class_name, superclass: grammar.superclass, start: grammar.start,
          mode: grammar.mode, starts: grammar.starts,
          expect: grammar.expect, expect_rr: grammar.expect_rr, options: grammar.options,
          parser_parameters: grammar.parser_parameters, value_printers: grammar.value_printers,
          grammar_tests: grammar.grammar_tests, recovery: grammar.recovery, lexer: grammar.lexer,
          symbols: grammar.symbols, productions: grammar.productions,
          user_code: grammar.user_code, user_code_chunks: grammar.user_code_chunks,
          conversions: grammar.conversions, warnings: grammar.warnings,
          source_provenance: grammar.source_provenance, migration: migration_to_v3(grammar),
          parser_contract: ParserContract.new
        )
      end
      module_function :migrate_grammar_to_v3

      # @rbs skip
      def migrate_automaton_to_v3(automaton)
        Automaton.v3(
          grammar: migrate_grammar_to_v3(automaton.grammar), states: automaton.states,
          conflict_summary: automaton.conflict_summary, algorithm: automaton.algorithm,
          entry_states: automaton.entry_states, entry_construction: "unknown"
        )
      end
      module_function :migrate_automaton_to_v3

      # @rbs skip
      def migration_to_v3(grammar)
        previous = grammar.migration
        unavailable = previous ? previous.fetch(:unavailable) : Array.new(0) #: Array[String]
        {
          from_schema_version: previous ? previous.fetch(:from_schema_version) : 2,
          unavailable: (unavailable + UNAVAILABLE_V2_CONFIGURATION).uniq
        }
      end
      module_function :migration_to_v3

      class << self
        private :migrate_grammar_to_v3, :migrate_automaton_to_v3, :migration_to_v3
      end
    end
  end
end
