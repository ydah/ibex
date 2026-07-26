# frozen_string_literal: true

module Ibex
  module Frontend
    # Tokenizes a racc-compatible grammar while preserving source locations.
    class Lexer
      PUNCTUATION = %w[: | ; = < > ? * + , ( )].to_h do |character|
        [character, character.to_sym]
      end.freeze #: Hash[String, Symbol]
      USER_CODE = /\A----[ \t]+(header|inner|footer)[ \t]*(?:\r?\n|\z)/ #: Regexp
      PERCENT_DIRECTIVES = {
        "%expect-rr" => [:identifier, "expect_rr"],
        "%precedence" => [:identifier, "precedence"],
        "%param" => [:identifier, "param"], "%printer" => [:identifier, "printer"],
        "%recover" => [:identifier, "recover"], "%on_error_reduce" => [:identifier, "on_error_reduce"],
        "%test" => [:identifier, "test"], "%inline" => [:inline, "%inline"],
        "%empty" => [:empty, "%empty"]
      }.freeze #: Hash[String, [Symbol, String]]

      # @rbs @cursor: SourceCursor
      # @rbs @segments: Array[Segment]
      # @rbs @emitted_tokens: Array[Token]
      # @rbs @eof_token: Token?
      # @rbs @active_token_start: SourcePosition?

      # @rbs (String source, ?file: String) -> void
      def initialize(source, file: "(grammar)")
        @cursor = SourceCursor.new(source, file)
        @segments = [] #: Array[Segment]
        @emitted_tokens = [] #: Array[Token]
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

      # @rbs () -> SourceDocument
      def tokenize_document
        tokenize unless @eof_token
        cst = CST::Document.new(@segments)
        SourceDocument.new(source: @cursor.source, file: @cursor.file, tokens: @emitted_tokens, cst: cst)
      end

      # @rbs () -> Token
      def next_token
        eof_token = @eof_token
        return eof_token if eof_token

        @active_token_start = nil
        skip_ignored
        start = @cursor.position
        @active_token_start = start
        scanned = if @cursor.eof?
                    token(:eof, nil)
                  else
                    scan_from_cursor
                  end
        emit_token(scanned, start) unless scanned.span
        @emitted_tokens << scanned
        @eof_token = scanned if scanned.type == :eof
        @active_token_start = nil
        scanned
      end

      private

      # @rbs () -> Token
      def scan_from_cursor
        character = @cursor.peek || ""

        return scan_user_code if line_start? && @cursor.rest.start_with?("----")
        return ActionScanner.new(@cursor).scan if character == "{"
        return scan_scope if @cursor.rest.start_with?("::")
        return scan_percent_directive if @cursor.peek == "%"

        scan_regular_token(character)
      end

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
          if newline?
            scan_newline
          elsif @cursor.peek&.match?(/\s/)
            scan_whitespace
          elsif @cursor.peek == "#"
            scan_line_comment
          elsif @cursor.rest.start_with?("/*")
            skip_block_comment
          else
            return
          end
        end
      end

      # @rbs () -> void
      def scan_whitespace
        start = @cursor.position
        @cursor.advance while @cursor.peek&.match?(/\s/) && !newline?
        emit_segment(:whitespace, start)
      end

      # @rbs () -> bool
      def newline?
        @cursor.peek == "\n" || @cursor.rest.start_with?("\r\n")
      end

      # @rbs () -> void
      def scan_newline
        start = @cursor.position
        @cursor.advance(@cursor.rest.start_with?("\r\n") ? 2 : 1)
        emit_segment(:newline, start)
      end

      # @rbs () -> void
      def scan_line_comment
        start = @cursor.position
        @cursor.advance until @cursor.eof? || newline?
        emit_segment(:line_comment, start)
      end

      # @rbs () -> void
      def skip_block_comment
        start = @cursor.position
        location = @cursor.location
        finish = @cursor.source.index("*/", @cursor.index + 2)
        raise Ibex::Error, "#{location}: unterminated block comment" unless finish

        @cursor.advance(finish + 2 - @cursor.index)
        emit_segment(:block_comment, start)
      end

      # @rbs () -> bool
      def line_start?
        @cursor.column == 1
      end

      # @rbs () -> Token
      def scan_user_code
        start_position = @cursor.position
        location = @cursor.location
        match = @cursor.rest.match(USER_CODE)
        raise Ibex::Error, "#{location}: expected ---- header, inner, or footer" unless match

        name = match[1]
        marker = match[0]
        raise Ibex::Error, "#{location}: expected ---- header, inner, or footer" unless name && marker

        @cursor.advance(marker.length)
        emit_segment(
          :user_code_marker, start_position, token_type: :user_code, token_index: @emitted_tokens.length
        )
        body_position = @cursor.position
        start = @cursor.index
        finish = @cursor.source.index(/^----/, start) || @cursor.source.length
        @cursor.advance(finish - start)
        code = @cursor.source[start...finish] || ""
        emit_segment(:user_code_body, body_position)
        token(:user_code, { name: name, code: code }, location, @cursor.span_from(start_position))
      end

      # @rbs () -> Token
      def scan_scope
        location = @cursor.location
        @cursor.advance(2)
        token(:scope, "::", location)
      end

      # @rbs () -> Token
      def scan_percent_directive
        location = @cursor.location
        directive = PERCENT_DIRECTIVES.each_key.find do |candidate|
          @cursor.rest.match?(/\A#{Regexp.escape(candidate)}(?=\s|\z)/)
        end
        raise Ibex::Error, "#{location}: unexpected character \"%\"" unless directive

        type, value = PERCENT_DIRECTIVES.fetch(directive)
        @cursor.advance(directive.length)
        token(type, value, location)
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

      # @rbs (Symbol type, token_value value, ?Location location, ?SourceSpan? span) -> Token
      def token(type, value, location = @cursor.location, span = nil)
        Token.new(type: type, value: value, location: location, span: span)
      end

      # @rbs (Token token, SourcePosition start) -> void
      def emit_token(token, start)
        token.span = @cursor.span_from(start)
        kind = case token.type
               when :action then :action
               when :eof then :eof
               else :token
               end
        emit_segment(kind, start, token_type: token.type, token_index: @emitted_tokens.length)
      end

      # @rbs (Symbol kind, SourcePosition start, ?token_type: Symbol?, ?token_index: Integer?) -> void
      def emit_segment(kind, start, token_type: nil, token_index: nil)
        span = @cursor.span_from(start)
        text = @cursor.source.byteslice(span.start_byte, span.length) || ""
        @segments << Segment.new(kind: kind, span: span, text: text,
                                 token_type: token_type, token_index: token_index)
      end
    end
  end
end
