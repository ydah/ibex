# frozen_string_literal: true

module Ibex
  # Selects Grammar IR v2 or v3 without changing declaration-free serialization.
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
      }
      return build_v2_grammar(keywords) unless parser_contract

      build_v3_grammar(keywords, parser_contract)
    end

    # @rbs (Hash[Symbol, untyped] keywords) -> IR::Grammar
    def build_v2_grammar(keywords)
      IR::Grammar.new(
        class_name: keywords.fetch(:class_name), superclass: keywords.fetch(:superclass),
        start: keywords.fetch(:start), expect: keywords.fetch(:expect), options: keywords.fetch(:options),
        symbols: keywords.fetch(:symbols), productions: keywords.fetch(:productions),
        user_code: keywords.fetch(:user_code), conversions: keywords.fetch(:conversions),
        warnings: keywords.fetch(:warnings), mode: keywords.fetch(:mode), starts: keywords.fetch(:starts),
        expect_rr: keywords.fetch(:expect_rr), parser_parameters: keywords.fetch(:parser_parameters),
        value_printers: keywords.fetch(:value_printers), grammar_tests: keywords.fetch(:grammar_tests),
        lexer: keywords.fetch(:lexer), recovery: keywords.fetch(:recovery),
        user_code_chunks: keywords.fetch(:user_code_chunks), source_provenance: keywords.fetch(:source_provenance)
      )
    end

    # @rbs (Hash[Symbol, untyped] keywords, IR::ParserContract parser_contract) -> IR::Grammar
    def build_v3_grammar(keywords, parser_contract)
      IR::Grammar.v3(
        class_name: keywords.fetch(:class_name), superclass: keywords.fetch(:superclass),
        start: keywords.fetch(:start), expect: keywords.fetch(:expect), options: keywords.fetch(:options),
        symbols: keywords.fetch(:symbols), productions: keywords.fetch(:productions),
        user_code: keywords.fetch(:user_code), conversions: keywords.fetch(:conversions),
        warnings: keywords.fetch(:warnings), mode: keywords.fetch(:mode), starts: keywords.fetch(:starts),
        expect_rr: keywords.fetch(:expect_rr), parser_parameters: keywords.fetch(:parser_parameters),
        value_printers: keywords.fetch(:value_printers), grammar_tests: keywords.fetch(:grammar_tests),
        lexer: keywords.fetch(:lexer), recovery: keywords.fetch(:recovery),
        user_code_chunks: keywords.fetch(:user_code_chunks), source_provenance: keywords.fetch(:source_provenance),
        parser_contract: parser_contract
      )
    end
  end
end
