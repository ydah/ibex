# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Classifies tokens through the class header and declaration section.
      class DeclarationState
        DECLARATIONS = {
          "token" => %i[TOKEN token_symbols], "options" => %i[OPTIONS options_identifiers],
          "expect" => %i[EXPECT expect_integer], "start" => %i[START start_symbol],
          "convert" => %i[CONVERT convert_name], "pragma" => %i[PRAGMA pragma_value],
          "rule" => %i[RULE rules]
        }.freeze #: Hash[String, [external_token, Symbol]]
        ASSOCIATIONS = {
          "left" => :LEFT, "right" => :RIGHT, "nonassoc" => :NONASSOC
        }.freeze #: Hash[String, external_token]
        SCALAR_TYPES = {
          literal: :LITERAL, integer: :INTEGER, action: :ACTION, user_code: :USER_CODE
        }.freeze #: Hash[Symbol, external_token]
        EXPECTATIONS = {
          class_keyword: "class", class_name: "identifier", superclass_name: "identifier",
          expect_integer: "integer", start_symbol: "a grammar symbol"
        }.freeze #: Hash[Symbol, String]

        attr_reader :conversion_name #: Token?
        attr_reader :declaration #: Symbol?
        attr_reader :precedence_closer #: String?
        attr_reader :state #: Symbol

        # @rbs () -> void
        def initialize
          @state = :class_keyword
        end

        # @rbs (Token token, Array[Token] remaining) -> external_token
        def classify(token, remaining)
          return classify_identifier(token, remaining) if token.type == :identifier
          return classify_scalar(token, remaining) if SCALAR_TYPES.key?(token.type)

          classify_punctuation(token)
        end

        # @rbs () -> bool
        def rules?
          @state == :rules
        end

        # @rbs () -> bool
        def extended_pragma?
          @extended_pragma == true
        end

        # @rbs (Token? token) -> String?
        def expectation(token)
          expected = EXPECTATIONS[@state]
          return expected if expected

          if @declaration == :precedence
            precedence_expectation(token)
          elsif @declaration == :convert
            "end"
          elsif @state == :declaration
            token&.type == :eof ? "rule" : "a declaration or rule"
          end
        end

        private

        # @rbs (Token token, Array[Token] remaining) -> external_token
        def classify_identifier(token, remaining)
          case @state
          when :class_keyword then class_keyword(token)
          when :class_name, :superclass_name then constant_name(remaining)
          when :declaration then begin_declaration(token)
          when :token_symbols, :options_identifiers then declaration_symbol(token)
          when :precedence_association, :precedence_symbols then precedence_identifier(token)
          when :start_symbol then finish_single_symbol(:IDENTIFIER)
          when :pragma_value then finish_pragma(token)
          when :convert_name then begin_conversion(token, :IDENTIFIER, remaining)
          else :IDENTIFIER
          end
        end

        # @rbs (Token token) -> external_token
        def class_keyword(token)
          return :IDENTIFIER unless string_value(token) == "class"

          @state = :class_name
          :CLASS
        end

        # @rbs (Array[Token] remaining) -> external_token
        def constant_name(remaining)
          following = remaining.first
          raise Ibex::Error, "unexpected end of token stream" unless following

          @state = if following.type == :scope
                     @state
                   elsif following.type == :<
                     :superclass_marker
                   else
                     :declaration
                   end
          :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def begin_declaration(token)
          value = string_value(token)
          return begin_precedence(token) if %w[prechigh preclow].include?(value)

          raise Ibex::Error, "#{token.location}: duplicate pragma extended" if value == "pragma" && @extended_pragma

          terminal, next_state = DECLARATIONS[value]
          return :IDENTIFIER unless terminal

          @state = next_state
          @declaration = value.to_sym unless terminal == :RULE
          @declaration = nil if terminal == :RULE
          terminal
        end

        # @rbs (Token token) -> external_token
        def finish_pragma(token)
          value = string_value(token)
          raise Ibex::Error, "#{token.location}: unknown pragma #{value}" unless value == "extended"

          @extended_pragma = true
          @state = :declaration
          @declaration = nil
          :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def begin_precedence(token)
          high_to_low = string_value(token) == "prechigh"
          @precedence_closer = high_to_low ? "preclow" : "prechigh"
          @declaration = :precedence
          @state = :precedence_association
          high_to_low ? :PRECHIGH : :PRECLOW
        end

        # @rbs (Token token) -> external_token
        def declaration_symbol(token)
          return begin_declaration(token) if declaration_boundary?(string_value(token))

          :IDENTIFIER
        end

        # @rbs (String value) -> bool
        def declaration_boundary?(value)
          DECLARATIONS.key?(value) || %w[prechigh preclow].include?(value)
        end

        # @rbs (Token token) -> external_token
        def precedence_identifier(token)
          value = string_value(token)
          return finish_precedence(token) if value == @precedence_closer

          association = ASSOCIATIONS[value]
          @state = :precedence_symbols if association
          association || :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def finish_precedence(token)
          @state = :declaration
          @declaration = nil
          @precedence_closer = nil
          string_value(token) == "prechigh" ? :PRECHIGH : :PRECLOW
        end

        # @rbs (Token token, external_token type, Array[Token] remaining) -> external_token
        def begin_conversion(token, type, remaining)
          if token.type == :identifier && token.value == "end"
            @state = :declaration
            @declaration = nil
            return :END
          end

          validate_conversion_line(token, remaining)
          @conversion_name = token
          @state = :convert_expression
          type
        end

        # @rbs (Token token, Array[Token] remaining) -> external_token
        def classify_scalar(token, remaining)
          type = SCALAR_TYPES.fetch(token.type)
          return finish_single_symbol(type) if @state == :expect_integer && type == :INTEGER
          return finish_single_symbol(type) if @state == :start_symbol && type == :LITERAL
          return begin_conversion(token, type, remaining) if @state == :convert_name && type == :LITERAL
          return finish_conversion(type) if @state == :convert_expression && type == :LITERAL

          type
        end

        # @rbs (external_token type) -> external_token
        def finish_single_symbol(type)
          @state = :declaration
          @declaration = nil
          type
        end

        # @rbs (external_token type) -> external_token
        def finish_conversion(type)
          @state = :convert_name
          @conversion_name = nil
          type
        end

        # @rbs (Token token) -> external_token
        def classify_punctuation(token)
          @state = :superclass_name if @state == :superclass_marker && token.type == :<
          string_value(token)
        end

        # @rbs (Token name, Array[Token] remaining) -> void
        def validate_conversion_line(name, remaining)
          line = name.location.line
          rest = remaining.take_while do |token|
            token.type != :eof && token.location.line == line && !(token.type == :identifier && token.value == "end")
          end
          return if rest.length == 1 && rest.first.type == :literal

          raise Ibex::Error, "#{name.location}: expected a quoted Ruby conversion expression"
        end

        # @rbs (Token? token) -> String?
        def precedence_expectation(token)
          return @precedence_closer if token&.type == :eof

          "left or right or nonassoc" if @state == :precedence_association
        end

        # @rbs (Token token) -> String
        def string_value(token)
          value = token.value
          return value if value.is_a?(String)

          raise Ibex::Error, "#{token.location}: expected text token"
        end
      end
    end
  end
end
