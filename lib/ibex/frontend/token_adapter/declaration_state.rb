# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Classifies tokens through the class header and declaration section.
      class DeclarationState
        DECLARATIONS = {
          "token" => %i[TOKEN token_symbols], "options" => %i[OPTIONS options_identifiers],
          "expect" => %i[EXPECT expect_integer], "start" => %i[START start_symbol],
          "convert" => %i[CONVERT convert_name], "rule" => %i[RULE rules]
        }.freeze
        ASSOCIATIONS = { "left" => :LEFT, "right" => :RIGHT, "nonassoc" => :NONASSOC }.freeze
        SCALAR_TYPES = { literal: :LITERAL, integer: :INTEGER, action: :ACTION, user_code: :USER_CODE }.freeze

        attr_reader :conversion_name, :declaration, :precedence_closer, :state

        def initialize
          @state = :class_keyword
        end

        def classify(token, remaining)
          return classify_identifier(token, remaining) if token.type == :identifier
          return classify_scalar(token, remaining) if SCALAR_TYPES.key?(token.type)

          classify_punctuation(token)
        end

        def rules?
          @state == :rules
        end

        private

        def classify_identifier(token, remaining)
          case @state
          when :class_keyword then class_keyword(token)
          when :class_name, :superclass_name then constant_name(remaining)
          when :declaration then begin_declaration(token)
          when :token_symbols, :options_identifiers then declaration_symbol(token)
          when :precedence_association, :precedence_symbols then precedence_identifier(token)
          when :start_symbol then finish_single_symbol(:IDENTIFIER)
          when :convert_name then begin_conversion(token, :IDENTIFIER, remaining)
          else :IDENTIFIER
          end
        end

        def class_keyword(token)
          @state = :class_name
          token.value == "class" ? :CLASS : :IDENTIFIER
        end

        def constant_name(remaining)
          @state = if remaining.first.type == :scope
                     @state
                   elsif remaining.first.type == :<
                     :superclass_marker
                   else
                     :declaration
                   end
          :IDENTIFIER
        end

        def begin_declaration(token)
          return begin_precedence(token) if %w[prechigh preclow].include?(token.value)

          terminal, next_state = DECLARATIONS[token.value]
          return :IDENTIFIER unless terminal

          @state = next_state
          @declaration = token.value.to_sym unless terminal == :RULE
          @declaration = nil if terminal == :RULE
          terminal
        end

        def begin_precedence(token)
          high_to_low = token.value == "prechigh"
          @precedence_closer = high_to_low ? "preclow" : "prechigh"
          @declaration = :precedence
          @state = :precedence_association
          high_to_low ? :PRECHIGH : :PRECLOW
        end

        def declaration_symbol(token)
          return begin_declaration(token) if declaration_boundary?(token.value)

          :IDENTIFIER
        end

        def declaration_boundary?(value)
          DECLARATIONS.key?(value) || %w[prechigh preclow].include?(value)
        end

        def precedence_identifier(token)
          return finish_precedence(token) if token.value == @precedence_closer

          association = ASSOCIATIONS[token.value]
          @state = :precedence_symbols if association
          association || :IDENTIFIER
        end

        def finish_precedence(token)
          @state = :declaration
          @declaration = nil
          @precedence_closer = nil
          token.value == "prechigh" ? :PRECHIGH : :PRECLOW
        end

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

        def classify_scalar(token, remaining)
          type = SCALAR_TYPES.fetch(token.type)
          return finish_single_symbol(type) if @state == :expect_integer && type == :INTEGER
          return finish_single_symbol(type) if @state == :start_symbol
          return begin_conversion(token, type, remaining) if @state == :convert_name && type == :LITERAL
          return finish_conversion(type) if @state == :convert_expression && type == :LITERAL

          type
        end

        def finish_single_symbol(type)
          @state = :declaration
          @declaration = nil
          type
        end

        def finish_conversion(type)
          @state = :convert_name
          @conversion_name = nil
          type
        end

        def classify_punctuation(token)
          @state = :superclass_name if @state == :superclass_marker && token.type == :<
          token.value
        end

        def validate_conversion_line(name, remaining)
          line = name.location.line
          rest = remaining.take_while do |token|
            token.type != :eof && token.location.line == line && !(token.type == :identifier && token.value == "end")
          end
          return if rest.length == 1 && rest.first.type == :literal

          raise Ibex::Error, "#{name.location}: expected a quoted Ruby conversion expression"
        end
      end
    end
  end
end
