# frozen_string_literal: true

module Ibex
  module LSP
    # Locates lossless frontend tokens used by the symbol index.
    module SymbolIndexSourceQueries
      private

      # @rbs (Frontend::SourceDocument document, Frontend::Location start,
      #   Frontend::Location? finish) -> Array[Frontend::Token]
      def tokens_between(document, start, finish)
        document.tokens.select do |token|
          after = !location_before?(token.location, start)
          before = finish.nil? || location_before?(token.location, finish)
          after && before
        end
      end

      # @rbs (Frontend::SourceDocument document, Frontend::Location location, String value) -> Frontend::Token?
      def token_at(document, location, value)
        document.tokens.find do |token|
          token.location.line == location.line && token.location.column == location.column && token.value == value
        end
      end

      # @rbs (Frontend::SourceDocument document, Frontend::Token lhs_token) -> Array[Frontend::Token]
      def parameter_tokens(document, lhs_token)
        start_index = document.tokens.index(lhs_token)
        return [] unless start_index

        tail = document.tokens.drop(start_index + 1)
        return [] unless tail.first&.type == :"("

        tail.take_while { |token| token.type != :")" }.select { |token| token.type == :identifier }
      end

      # @rbs (Frontend::AST::declaration declaration) -> Array[String]
      def declaration_reference_names(declaration)
        case declaration
        when Frontend::AST::Start
          declaration.names
        when Frontend::AST::DisplayName, Frontend::AST::SemanticType
          [declaration.name]
        when Frontend::AST::Convert
          declaration.pairs.map(&:name)
        when Frontend::AST::Precedence
          declaration.levels.flat_map(&:symbols)
        else
          []
        end
      end

      # @rbs (Frontend::Location left, Frontend::Location right) -> bool
      def location_before?(left, right)
        left.line < right.line || (left.line == right.line && left.column < right.column)
      end
    end
  end
end
