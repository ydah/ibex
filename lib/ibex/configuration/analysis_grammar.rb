# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Configuration
    # Produces an immutable Grammar IR view suitable for an explicitly
    # noncanonical analysis algorithm. The source-owned contract remains the
    # authority; callers must report the override through Configuration::Value.
    module AnalysisGrammar
      module_function

      # @rbs (IR::Grammar grammar, Symbol algorithm) -> IR::Grammar
      def for_algorithm(grammar, algorithm)
        contract = grammar.parser_contract
        return grammar unless contract&.algorithm&.explicit
        return grammar if contract.algorithm.value == algorithm

        analysis_contract = IR::ParserContract.new(
          algorithm: IR::ParserContract::Entry.new(:algorithm),
          entries: contract.entries, cst_trivia: contract.cst_trivia
        )
        IR::Grammar.new(
          class_name: grammar.class_name, superclass: grammar.superclass, start: grammar.start,
          expect: grammar.expect, options: grammar.options, symbols: grammar.symbols,
          productions: grammar.productions, user_code: grammar.user_code, conversions: grammar.conversions,
          warnings: grammar.warnings, expect_rr: grammar.expect_rr, user_code_chunks: grammar.user_code_chunks,
          source_provenance: grammar.source_provenance,
          parser_parameters: grammar.parser_parameters, value_printers: grammar.value_printers,
          grammar_tests: grammar.grammar_tests, recovery: grammar.recovery, lexer: grammar.lexer,
          mode: grammar.mode, starts: grammar.starts, parser_contract: analysis_contract
        )
      end
    end
  end
end
