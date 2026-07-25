# frozen_string_literal: true

module Ibex
  module Frontend
    # Public grammar parser backed by Ibex's generated LR frontend.
    class Parser
      attr_reader :implementation #: GeneratedParser

      # @rbs @source_document: SourceDocument?
      # @rbs @parsed_document: SourceDocument?
      # @rbs @ast: AST::Root?

      # @rbs (String | Array[Token] source, ?file: String, ?mode: Symbol) -> void
      def initialize(source, file: "(grammar)", mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        if source.is_a?(Array)
          tokens = source
        else
          source_document = Lexer.new(source, file: file).tokenize_document
          @source_document = source_document
          tokens = source_document.tokens
        end
        @implementation = GeneratedParser.new(tokens, mode: mode)
      end

      # @rbs () -> AST::Root
      def parse
        ast = @ast
        return ast if ast

        @ast = @implementation.parse
      end

      # Parse the grammar and return its lossless source model.
      # @rbs () -> SourceDocument
      def parse_document
        source_document = @source_document
        raise ArgumentError, "parse_document requires String source" unless source_document

        parsed_document = @parsed_document
        return parsed_document if parsed_document

        @parsed_document = source_document.with_ast(parse)
      end
    end
  end
end
