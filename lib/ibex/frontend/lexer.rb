# frozen_string_literal: true

module Ibex
  module Frontend
    # Tokenizes a racc-compatible grammar while preserving source locations.
    class Lexer
      PUNCTUATION = %w[: | ; = < > ? * + , ( )].to_h { |character| [character, character.to_sym] }.freeze
      USER_CODE = /\A----[ \t]+(header|inner|footer)[ \t]*(?:\r?\n|\z)/

      def initialize(source, file: "(grammar)")
        @cursor = SourceCursor.new(source, file)
      end

      def tokenize
        tokens = [] #: Array[untyped]
        loop do
          token = next_token
          tokens << token
          return tokens if token.type == :eof
        end
      end

      def next_token
        skip_ignored
        return token(:eof, nil) if @cursor.eof?
        return scan_user_code if line_start? && @cursor.rest.start_with?("----")
        return ActionScanner.new(@cursor).scan if @cursor.peek == "{"
        return scan_scope if @cursor.rest.start_with?("::")
        return scan_identifier if @cursor.peek.match?(/[A-Za-z_]/)
        return scan_integer if @cursor.peek.match?(/\d/)
        return scan_literal if ["'", '"'].include?(@cursor.peek)
        return scan_punctuation if PUNCTUATION.key?(@cursor.peek)

        raise Ibex::Error, "#{@cursor.location}: unexpected character #{@cursor.peek.inspect}"
      end

      private

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

      def skip_block_comment
        location = @cursor.location
        finish = @cursor.source.index("*/", @cursor.index + 2)
        raise Ibex::Error, "#{location}: unterminated block comment" unless finish

        @cursor.advance(finish + 2 - @cursor.index)
      end

      def line_start?
        @cursor.column == 1
      end

      def scan_user_code
        location = @cursor.location
        match = @cursor.rest.match(USER_CODE)
        raise Ibex::Error, "#{location}: expected ---- header, inner, or footer" unless match

        name = match[1]
        @cursor.advance(match[0].length)
        start = @cursor.index
        finish = @cursor.source.index(/^----/, start) || @cursor.source.length
        @cursor.advance(finish - start)
        token(:user_code, { name: name, code: @cursor.source[start...finish] }, location)
      end

      def scan_scope
        location = @cursor.location
        @cursor.advance(2)
        token(:scope, "::", location)
      end

      def scan_identifier
        scan_match(:identifier, /\A[A-Za-z_][A-Za-z0-9_]*/)
      end

      def scan_integer
        scan_match(:integer, /\A\d+/) { |value| Integer(value, 10) }
      end

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
            return token(:literal, @cursor.source[start...@cursor.index], location)
          else
            @cursor.advance
          end
        end
        raise Ibex::Error, "#{location}: unterminated quoted token"
      end

      def scan_punctuation
        location = @cursor.location
        character = @cursor.peek
        @cursor.advance
        token(PUNCTUATION.fetch(character), character, location)
      end

      # @rbs (untyped type, Regexp pattern) ?{ (String) -> untyped } -> untyped
      def scan_match(type, pattern)
        location = @cursor.location
        value = @cursor.rest.match(pattern)[0]
        @cursor.advance(value.length)
        value = yield(value) if block_given?
        token(type, value, location)
      end

      def token(type, value, location = @cursor.location)
        Token.new(type: type, value: value, location: location)
      end
    end
  end
end
