# frozen_string_literal: true

module Ibex
  module IR
    # Meaning-preserving upgrades between published IR schema versions.
    module Migration
      UNAVAILABLE_V1_METADATA = %w[
        source_provenance
        symbol_docs
        production_docs
        production_expansion
        action_composition
        grammar_tests
        lexer
      ].freeze #: Array[String]

      # @rbs (Grammar | Automaton value, ?to: Integer) -> (Grammar | Automaton)
      def to_version(value, to: SCHEMA_VERSION)
        return value if value.schema_version == to
        return to_v2(value) if value.schema_version == 1 && to == 2

        raise Ibex::Error,
              "(ir):1:1: cannot migrate schema_version #{value.schema_version} to #{to}; only 1 to 2 is supported"
      end
      module_function :to_version

      # @rbs (Grammar | Automaton value) -> (Grammar | Automaton)
      def to_v2(value)
        return value if value.schema_version == 2
        unless value.schema_version == 1
          raise Ibex::Error, "(ir):1:1: cannot migrate unsupported schema_version #{value.schema_version}"
        end

        return migrate_grammar(value) if value.is_a?(Grammar)
        return migrate_automaton(value) if value.is_a?(Automaton)

        raise Ibex::Error, "(ir):1:1: cannot migrate unsupported IR object #{value.class}"
      end
      module_function :to_v2

      # @rbs (Grammar grammar) -> Grammar
      def migrate_grammar(grammar)
        symbols = migrate_symbols(grammar)
        productions = migrate_productions(grammar)
        build_migrated_grammar(grammar, symbols, productions)
      end
      module_function :migrate_grammar

      # @rbs (Grammar grammar) -> Array[GrammarSymbol]
      def migrate_symbols(grammar)
        grammar.symbols.map do |symbol|
          GrammarSymbol.new(
            id: symbol.id, name: symbol.name, kind: symbol.kind, reserved: symbol.reserved,
            precedence: symbol.precedence, location: symbol.location, display_name: symbol.display_name,
            semantic_type: symbol.semantic_type
          )
        end
      end
      module_function :migrate_symbols

      # @rbs (Grammar grammar) -> Array[Production]
      def migrate_productions(grammar)
        grammar.productions.map do |production|
          Production.new(
            id: production.id, lhs: production.lhs, rhs: production.rhs,
            action: migrate_action(production.action), precedence_override: production.precedence_override,
            origin: production.origin
          )
        end
      end
      module_function :migrate_productions

      # @rbs (Grammar grammar, Array[GrammarSymbol] symbols, Array[Production] productions) -> Grammar
      def build_migrated_grammar(grammar, symbols, productions)
        Grammar.new(
          class_name: grammar.class_name, superclass: grammar.superclass, start: grammar.start,
          mode: grammar.mode, starts: grammar.starts,
          expect: grammar.expect, expect_rr: grammar.expect_rr, options: grammar.options,
          parser_parameters: grammar.parser_parameters,
          value_printers: grammar.value_printers,
          grammar_tests: grammar.grammar_tests,
          recovery: grammar.recovery,
          symbols: symbols, productions: productions,
          user_code: grammar.user_code, user_code_chunks: grammar.user_code_chunks,
          conversions: grammar.conversions, warnings: grammar.warnings, schema_version: 2,
          migration: { from_schema_version: 1, unavailable: UNAVAILABLE_V1_METADATA }
        )
      end
      module_function :build_migrated_grammar

      # @rbs (Action? action) -> Action?
      def migrate_action(action)
        return nil unless action

        Action.new(
          code: action.code, location: action.location, named_refs: action.named_refs,
          context_length: action.context_length
        )
      end
      module_function :migrate_action

      # @rbs (Automaton automaton) -> Automaton
      def migrate_automaton(automaton)
        Automaton.new(
          grammar: migrate_grammar(automaton.grammar), states: automaton.states,
          conflict_summary: automaton.conflict_summary, algorithm: automaton.algorithm, schema_version: 2,
          entry_states: automaton.entry_states
        )
      end
      module_function :migrate_automaton

      class << self
        private :migrate_grammar, :migrate_symbols, :migrate_productions, :build_migrated_grammar,
                :migrate_action, :migrate_automaton
      end
    end
  end
end
