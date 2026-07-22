# frozen_string_literal: true

module Ibex
  module Frontend
    # Tokenizes a racc-compatible grammar while preserving source locations.
    class Lexer
      PUNCTUATION = %w[: | ; = < > ? * + , ( )].to_h { |character| [character, character.to_sym] }.freeze
      USER_CODE = /\A----[ \t]+(header|inner|footer)[ \t]*(?:\r?\n|\z)/

      # @rbs @cursor: SourceCursor

      # @rbs (String source, ?file: String) -> void
      def initialize(source, file: "(grammar)")
        @cursor = SourceCursor.new(source, file)
      end

      # @rbs () -> Array[Token]
      def tokenize
        tokens = [] #: Array[Token]
        loop do
          token = next_token
          tokens << token
          return tokens if token.type == :eof
        end
      end

      # @rbs () -> Token
      def next_token
        skip_ignored
        return token(:eof, nil) if @cursor.eof?

        character = @cursor.peek || ""

        return scan_user_code if line_start? && @cursor.rest.start_with?("----")
        return ActionScanner.new(@cursor).scan if character == "{"
        return scan_scope if @cursor.rest.start_with?("::")

        scan_regular_token(character)
      end

      private

      # @rbs (String character) -> Token
      def scan_regular_token(character)
        return scan_identifier if character.match?(/[A-Za-z_]/)
        return scan_integer if character.match?(/\d/)
        return scan_literal if ["'", '"'].include?(character)
        return scan_punctuation if PUNCTUATION.key?(character)

        raise Ibex::Error, "#{@cursor.location}: unexpected character #{character.inspect}"
      end

      # @rbs () -> void
      def skip_ignored
        loop do
          @cursor.advance while @cursor.peek&.match?(/\s/)
          if @cursor.peek == "#"
            @cursor.advance until @cursor.eof? || @cursor.peek == "\n"
          elsif @cursor.rest.start_with?("/*")
            skip_block_comment
          else
            return
          end
        end
      end

      # @rbs () -> void
      def skip_block_comment
        location = @cursor.location
        finish = @cursor.source.index("*/", @cursor.index + 2)
        raise Ibex::Error, "#{location}: unterminated block comment" unless finish

        @cursor.advance(finish + 2 - @cursor.index)
      end

      # @rbs () -> bool
      def line_start?
        @cursor.column == 1
      end

      # @rbs () -> Token
      def scan_user_code
        location = @cursor.location
        match = @cursor.rest.match(USER_CODE)
        raise Ibex::Error, "#{location}: expected ---- header, inner, or footer" unless match

        name = match[1]
        marker = match[0]
        raise Ibex::Error, "#{location}: expected ---- header, inner, or footer" unless name && marker

        @cursor.advance(marker.length)
        start = @cursor.index
        finish = @cursor.source.index(/^----/, start) || @cursor.source.length
        @cursor.advance(finish - start)
        code = @cursor.source[start...finish] || ""
        token(:user_code, { name: name, code: code }, location)
      end

      # @rbs () -> Token
      def scan_scope
        location = @cursor.location
        @cursor.advance(2)
        token(:scope, "::", location)
      end

      # @rbs () -> Token
      def scan_identifier
        scan_match(:identifier, /\A[A-Za-z_][A-Za-z0-9_]*/)
      end

      # @rbs () -> Token
      def scan_integer
        scan_match(:integer, /\A\d+/) { |value| Integer(value, 10) }
      end

      # @rbs () -> Token
      def scan_literal
        location = @cursor.location
        quote = @cursor.peek
        start = @cursor.index
        @cursor.advance
        until @cursor.eof?
          if @cursor.peek == "\\"
            @cursor.advance(2)
          elsif @cursor.peek == quote
            @cursor.advance
            value = @cursor.source[start...@cursor.index] || ""
            return token(:literal, value, location)
          else
            @cursor.advance
          end
        end
        raise Ibex::Error, "#{location}: unterminated quoted token"
      end

      # @rbs () -> Token
      def scan_punctuation
        location = @cursor.location
        character = @cursor.peek
        raise Ibex::Error, "#{location}: expected punctuation" unless character

        @cursor.advance
        token(PUNCTUATION.fetch(character), character, location)
      end

      # @rbs (Symbol type, Regexp pattern) ?{ (String) -> token_value } -> Token
      def scan_match(type, pattern)
        location = @cursor.location
        value = @cursor.rest.match(pattern)&.[](0)
        raise Ibex::Error, "#{location}: invalid #{type} token" unless value

        @cursor.advance(value.length)
        value = yield(value) if block_given?
        token(type, value, location)
      end

      # @rbs (Symbol type, token_value value, ?Location location) -> Token
      def token(type, value, location = @cursor.location)
        Token.new(type: type, value: value, location: location)
      end
    end
  end
end
