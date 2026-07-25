# frozen_string_literal: true

module Ibex
  module Frontend
    # Public grammar parser backed by Ibex's generated LR frontend.
    class Parser
      DEFAULT_MAX_DIAGNOSTICS = 20 #: Integer
      STRICT_LEXICAL_DIAGNOSTIC_LIMIT = 1 #: Integer
      private_constant :STRICT_LEXICAL_DIAGNOSTIC_LIMIT

      attr_reader :implementation #: GeneratedParser

      # @rbs @source_document: SourceDocument?
      # @rbs @parsed_document: SourceDocument?
      # @rbs @parsed_node: AST::Root | AST::Fragment | nil
      # @rbs @parse_error_message: String?
      # @rbs @source_document_error_message: String?
      # @rbs @tokens: Array[Token]
      # @rbs @mode: Symbol
      # @rbs @lexical_diagnostics: Array[Diagnostic]

      # @rbs (String | Array[Token] source, ?file: String, ?mode: Symbol) -> void
      def initialize(source, file: "(grammar)", mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        @mode = mode
        @lexical_diagnostics = [] #: Array[Diagnostic]
        @parse_error_message = nil
        @source_document_error_message = nil
        tokens = source.is_a?(Array) ? source : tokenize_source(source, file)
        @tokens = tokens
        @implementation = GeneratedParser.new(tokens, mode: mode)
      end

      # @rbs () -> AST::Root
      def parse
        node = parse_node
        return node if node.is_a?(AST::Root)

        raise Ibex::Error, "#{node.loc}: fragment input requires Parser#parse_fragment"
      end

      # Parse an explicit fragment without resolving its includes.
      # @rbs () -> AST::Fragment
      def parse_fragment
        node = parse_node
        return node if node.is_a?(AST::Fragment)

        raise Ibex::Error, "#{node.loc}: root grammar input cannot be parsed as a fragment"
      end

      # Parse the grammar and return its lossless source model.
      # @rbs () -> SourceDocument
      def parse_document
        source_document_error_message = @source_document_error_message
        raise Ibex::Error, source_document_error_message if source_document_error_message

        source_document = @source_document
        raise ArgumentError, "parse_document requires String source" unless source_document

        parsed_document = @parsed_document
        return parsed_document if parsed_document

        @parsed_document = source_document.with_ast(parse)
      end

      # Parse with conservative boundary recovery and collect multiple errors.
      # @rbs (?max_diagnostics: Integer) -> ParseResult
      def parse_with_diagnostics(max_diagnostics: DEFAULT_MAX_DIAGNOSTICS)
        unless max_diagnostics.is_a?(Integer) && max_diagnostics.positive?
          raise ArgumentError, "max_diagnostics must be a positive integer"
        end

        lexical_diagnostics = lexical_diagnostics_for(max_diagnostics)
        if @source_document.nil? && @lexical_diagnostics.any?
          return ParseResult.new(diagnostics: lexical_diagnostics, ast: nil, document: nil)
        end

        recovery = DiagnosticRecovery.new(
          @tokens, mode: @mode, max_diagnostics: max_diagnostics
        )
        node, syntax_diagnostics = recovery.parse
        ast, syntax_diagnostics = root_diagnostic_result(node, syntax_diagnostics)
        diagnostics = merge_diagnostics(lexical_diagnostics, syntax_diagnostics, max_diagnostics)
        document = if diagnostics.empty? && ast
                     @source_document&.with_ast(ast)
                   else
                     @source_document
                   end
        ParseResult.new(diagnostics: diagnostics, ast: ast, document: document)
      end

      private

      # @rbs () -> (AST::Root | AST::Fragment)
      def parse_node
        lexical = @lexical_diagnostics.first
        raise Ibex::Error, lexical.to_s if lexical

        parse_error_message = @parse_error_message
        raise Ibex::Error, parse_error_message if parse_error_message

        node = @parsed_node
        return node if node

        begin
          @parsed_node = @implementation.parse
        rescue Ibex::Error => e
          @parse_error_message = e.message.dup.freeze
          raise
        end
      end

      # @rbs (AST::Root | AST::Fragment | nil node, Array[Diagnostic] diagnostics) ->
      #   [AST::Root?, Array[Diagnostic]]
      def root_diagnostic_result(node, diagnostics)
        return [node, diagnostics] unless node.is_a?(AST::Fragment)

        diagnostic = Diagnostic.new(
          code: "frontend.syntax_error", phase: :syntax,
          message: "fragment input requires Parser#parse_fragment", location: node.loc
        )
        [nil, diagnostics + [diagnostic]]
      end

      # @rbs (String source, String file) -> Array[Token]
      def tokenize_source(source, file)
        document, diagnostics = Lexer.new(source, file: file).tokenize_document_recovering(
          max_diagnostics: STRICT_LEXICAL_DIAGNOSTIC_LIMIT
        )
        @source_document = document
        @lexical_diagnostics = diagnostics
        document.tokens
      rescue Ibex::Error => e
        location = Location.new(file: file, line: 1, column: 1)
        @lexical_diagnostics = [
          Diagnostic.new(code: "frontend.lexical_error", phase: :lexical, message: e.message,
                         location: location, rendered: e.message)
        ]
        @source_document_error_message = e.message.dup.freeze
        [Token.new(type: :eof, value: nil, location: location, span: nil)]
      end

      # @rbs (Integer max_diagnostics) -> Array[Diagnostic]
      def lexical_diagnostics_for(max_diagnostics)
        return @lexical_diagnostics if @lexical_diagnostics.empty? || max_diagnostics == 1

        source_document = @source_document
        return @lexical_diagnostics.first(max_diagnostics) unless source_document

        _, diagnostics = Lexer.new(source_document.source, file: source_document.file)
                              .tokenize_document_recovering(max_diagnostics: max_diagnostics)
        diagnostics
      end

      # @rbs (Array[Diagnostic] lexical, Array[Diagnostic] syntax, Integer limit) -> Array[Diagnostic]
      def merge_diagnostics(lexical, syntax, limit)
        (lexical + syntax)
          .uniq { |diagnostic| diagnostic_key(diagnostic) }
          .sort_by { |diagnostic| diagnostic_sort_key(diagnostic) }
          .first(limit)
          .freeze
      end

      # @rbs (Diagnostic diagnostic) -> [String, String, Integer, Integer, String]
      def diagnostic_key(diagnostic)
        location = diagnostic.location
        [diagnostic.phase.to_s, location.file, location.line, location.column, diagnostic.message]
      end

      # @rbs (Diagnostic diagnostic) -> [String, Integer, Integer, String, String]
      def diagnostic_sort_key(diagnostic)
        location = diagnostic.location
        [location.file, location.line, location.column, diagnostic.phase.to_s, diagnostic.code]
      end
    end
  end
end
