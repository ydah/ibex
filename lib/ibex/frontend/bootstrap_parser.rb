# frozen_string_literal: true

module Ibex
  module Frontend
    # Handwritten parser used only to regenerate the self-hosted frontend.
    class BootstrapParser
      include BootstrapParserDeclarations
      include BootstrapParserRules

      def initialize(source, file: "(grammar)", mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        @tokens = source.is_a?(Array) ? source : Lexer.new(source, file: file).tokenize
        @index = 0
        @mode = mode
      end

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

      def parse_constant_path
        parts = [expect(:identifier).value]
        parts << expect(:identifier).value while accept(:scope)
        parts.join("::")
      end

      def parse_symbol_name
        expect_symbol.value
      end

      def expect_symbol
        return advance if %i[identifier literal].include?(current.type)

        fail_expected("a grammar symbol")
      end

      def expect_one_of(values)
        return advance if current.type == :identifier && values.include?(current.value)

        fail_expected(values.join(" or "))
      end

      def keyword?(value)
        current.type == :identifier && current.value == value
      end

      def expect_keyword(value)
        return advance if keyword?(value)

        fail_expected(value)
      end

      def accept(type)
        return false unless current.type == type

        advance
      end

      def expect(type)
        return advance if current.type == type

        fail_expected(type)
      end

      def current
        @tokens.fetch(@index)
      end

      def lookahead
        @tokens.fetch(@index + 1, @tokens.last)
      end

      def advance
        token = current
        @index += 1
        token
      end

      def parse_user_code
        blocks = Hash.new { |hash, key| hash[key] = Array.new(0) } #: Hash[untyped, Array[untyped]]
        while current.type == :user_code
          token = advance
          value = token.value
          blocks[value[:name]] << AST::UserCode.new(name: value[:name], code: value[:code], loc: token.location)
        end
        blocks
      end

      def extended_only!(location, feature)
        return if @mode == :extended

        fail_at(location, "#{feature} require extended mode")
      end

      def fail_expected(expected)
        fail_at(current.location, "expected #{expected}, got #{current.value || current.type}")
      end

      def fail_at(location, message)
        raise Ibex::Error, "#{location}: #{message}"
      end
    end
  end
end
