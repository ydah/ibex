# frozen_string_literal: true

module Ibex
  module Frontend
    # Builds extended symbol metadata declarations for the generated grammar parser.
    module GeneratedParserMetadata
      private

      # @rbs (Token keyword, Token name, Token value) -> AST::DisplayName
      def build_display_name(keyword, name, value)
        # @type self: GeneratedParserBase
        extended_only!(keyword.location, "display declarations")
        result = build_symbol_metadata(AST::DisplayName, keyword, name, value, "display")
        return result if result.is_a?(AST::DisplayName)

        raise Ibex::Error, "display metadata builder returned the wrong node"
      end

      # @rbs (Token keyword, Token name, Token value) -> AST::SemanticType
      def build_semantic_type(keyword, name, value)
        # @type self: GeneratedParserBase
        extended_only!(keyword.location, "type declarations")
        result = build_symbol_metadata(AST::SemanticType, keyword, name, value, "type")
        return result if result.is_a?(AST::SemanticType)

        raise Ibex::Error, "type metadata builder returned the wrong node"
      end

      # @rbs (singleton(AST::DisplayName) | singleton(AST::SemanticType) node_class,
      #   Token keyword, Token name, Token value, String feature) -> (AST::DisplayName | AST::SemanticType)
      def build_symbol_metadata(node_class, keyword, name, value, feature)
        # @type self: GeneratedParserBase
        unless keyword.location.line == name.location.line && name.location.line == value.location.line
          fail_at(keyword.location, "#{feature} declaration must be written on one line")
        end

        decoded = decode_metadata_value(value, feature)
        node_class.new(name: token_string(name), value: decoded, loc: keyword.location)
      end

      # @rbs (Token token, String feature) -> String
      def decode_metadata_value(token, feature)
        # @type self: GeneratedParserBase
        literal = token_string(token)
        decoded = if literal.start_with?('"')
                    literal.undump
                  else
                    (literal[1...-1] || "").gsub("\\'", "'").gsub("\\\\", "\\")
                  end
        fail_at(token.location, "#{feature} value must not be empty") if decoded.strip.empty?
        fail_at(token.location, "#{feature} value must be a single line") if decoded.match?(/[\r\n]/)
        fail_at(token.location, "#{feature} value must not contain control characters") if
          decoded.match?(/[[:cntrl:]]/)

        decoded
      rescue RuntimeError => e
        fail_at(token.location, "invalid #{feature} value: #{e.message}")
      end
    end
  end
end
