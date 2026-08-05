# frozen_string_literal: true

module Ibex
  # Selects Grammar IR v2 or v3 without changing declaration-free serialization.
  module NormalizeGrammarBuilder
    private

    # @rbs (IR::ParserContract? parser_contract) -> IR::Grammar
    def build_grammar(parser_contract)
      # @type self: Normalizer
      attributes = {
        class_name: @ast.class_name, superclass: @ast.superclass, start: @start_name,
        expect: @expected_conflicts, options: @options, symbols: @symbols,
        mode: @mode, starts: @start_names, expect_rr: @expected_rr_conflicts,
        parser_parameters: @parser_parameters, value_printers: @value_printers.values,
        grammar_tests: @grammar_tests, lexer: normalize_lexer,
        recovery: { sync_tokens: @recovery_sync_tokens, on_error_reduce: @on_error_reduce_groups },
        productions: @productions, user_code: normalized_user_code,
        conversions: @conversions, warnings: @warnings, user_code_chunks: normalized_user_code_chunks,
        source_provenance: { file: @ast.loc.file, root: @resolution&.root_directory, byte_span: nil }
      }
      return IR::Grammar.new(**attributes) unless parser_contract

      IR::Grammar.v3(**attributes, parser_contract: parser_contract)
    end
  end
end
