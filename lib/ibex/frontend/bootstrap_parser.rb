# frozen_string_literal: true

module Ibex
  module Frontend
    # Handwritten parser used only to regenerate the self-hosted frontend.
    class BootstrapParser
      include BootstrapParserDeclarations
      include BootstrapParserRules

      # @rbs @tokens: Array[Token]
      # @rbs @index: Integer
      # @rbs @mode: Symbol

      # @rbs (String | Array[Token] source, ?file: String, ?mode: Symbol) -> void
      def initialize(source, file: "(grammar)", mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        @tokens = source.is_a?(Array) ? source : Lexer.new(source, file: file).tokenize
        @index = 0
        @mode = mode
      end

      # @rbs () -> AST::Root
      def parse
        location = expect_keyword("class").location
        class_name = parse_constant_path
        superclass = accept(:<) ? parse_constant_path : nil
        declarations = parse_declarations
        expect_keyword("rule")
        rules = parse_rules
        expect_keyword("end")
        user_code = parse_user_code
        expect(:eof)
        AST::Root.new(class_name: class_name, superclass: superclass, declarations: declarations,
                      rules: rules, user_code: user_code, loc: location)
      end

      private

      # @rbs () -> String
      def parse_constant_path
        parts = [token_string(expect(:identifier))]
        parts << token_string(expect(:identifier)) while accept(:scope)
        parts.join("::")
      end

      # @rbs () -> String
      def parse_symbol_name
        token_string(expect_symbol)
      end

      # @rbs () -> Token
      def expect_symbol
        return advance if %i[identifier literal].include?(current.type)

        fail_expected("a grammar symbol")
      end

      # @rbs (Array[String] values) -> Token
      def expect_one_of(values)
        return advance if current.type == :identifier && values.include?(current.value)

        fail_expected(values.join(" or "))
      end

      # @rbs (String value) -> bool
      def keyword?(value)
        current.type == :identifier && current.value == value
      end

      # @rbs (String value) -> Token
      def expect_keyword(value)
        return advance if keyword?(value)

        fail_expected(value)
      end

      # @rbs (Symbol type) -> (Token | false)
      def accept(type)
        return false unless current.type == type

        advance
      end

      # @rbs (Symbol type) -> Token
      def expect(type)
        return advance if current.type == type

        fail_expected(type)
      end

      # @rbs () -> Token
      def current
        @tokens.fetch(@index)
      end

      # @rbs () -> Token
      def lookahead
        @tokens.fetch(@index + 1) { @tokens.fetch(-1) }
      end

      # @rbs () -> Token
      def advance
        token = current
        @index += 1
        token
      end

      # @rbs () -> AST::user_code
      def parse_user_code
        blocks = Hash.new { |hash, key| hash[key] = Array.new(0) } #: AST::user_code
        while current.type == :user_code
          token = advance
          value = token_user_code(token)
          blocks[value[:name]] << AST::UserCode.new(name: value[:name], code: value[:code], loc: token.location)
        end
        blocks
      end

      # @rbs (Location location, String feature) -> void
      def extended_only!(location, feature)
        return if @mode == :extended

        fail_at(location, "#{feature} require extended mode")
      end

      # @rbs (String | Symbol expected) -> bot
      def fail_expected(expected)
        fail_at(current.location, "expected #{expected}, got #{current.value || current.type}")
      end

      # @rbs (Location location, String message) -> bot
      def fail_at(location, message)
        raise Ibex::Error, "#{location}: #{message}"
      end

      # @rbs (Token token) -> String
      def token_string(token)
        value = token.value
        return value if value.is_a?(String)

        fail_at(token.location, "expected text token")
      end

      # @rbs (Token token) -> Integer
      def token_integer(token)
        value = token.value
        return value if value.is_a?(Integer)

        fail_at(token.location, "expected integer token")
      end

      # @rbs (Token token) -> user_code_token
      def token_user_code(token)
        value = token.value
        return value if value.is_a?(Hash)

        fail_at(token.location, "expected user-code token")
      end
    end
  end
end
