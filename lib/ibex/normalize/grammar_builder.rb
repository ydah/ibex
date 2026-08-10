# frozen_string_literal: true

module Ibex
  # Builds the single current Grammar IR format for every normalized source.
  module NormalizeGrammarBuilder
    private

    # @rbs (IR::ParserContract? parser_contract) -> IR::Grammar
    def build_grammar(parser_contract)
      # @type self: Normalizer
      keywords = {
        class_name: @ast.class_name, superclass: @ast.superclass, start: @start_name,
        expect: @expected_conflicts, options: @options, symbols: @symbols,
        mode: @mode, starts: @start_names, expect_rr: @expected_rr_conflicts,
        parser_parameters: @parser_parameters, value_printers: @value_printers.values,
        grammar_tests: @grammar_tests, lexer: normalize_lexer,
        recovery: { sync_tokens: @recovery_sync_tokens, on_error_reduce: @on_error_reduce_groups },
        productions: @productions, user_code: normalized_user_code,
        conversions: @conversions, warnings: @warnings, user_code_chunks: normalized_user_code_chunks,
        source_provenance: { file: @ast.loc.file, root: @resolution&.root_directory, byte_span: nil }
      } #: { class_name: String, superclass: String?, start: String, expect: Integer, options: IR::grammar_options, symbols: Array[IR::GrammarSymbol], productions: Array[IR::Production], user_code: Hash[String, String], conversions: Hash[String, String], warnings: Array[IR::grammar_warning] } # rubocop:disable Layout/LineLength -- inline Steep shape mirrors the normalized builder contract.

      IR::Grammar.new(**keywords, parser_contract: parser_contract || IR::ParserContract.new) # steep:ignore Ruby::InsufficientKeywordArguments
    end
  end
end
