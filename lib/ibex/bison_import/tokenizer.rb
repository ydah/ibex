# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module BisonImport
    # Iterative scanner for the punctuation needed to recover Bison rules.
    class Tokenizer
      # One structural token with a byte-oriented source position.
      class Token
        attr_reader :type #: Symbol
        attr_reader :value #: String
        attr_reader :line #: Integer
        attr_reader :column #: Integer

        # @rbs (type: Symbol, value: String, line: Integer, column: Integer) -> void
        def initialize(type:, value:, line:, column:)
          @type = type
          @value = value.freeze
          @line = line
          @column = column
          freeze
        end
      end

      IDENTIFIER_START = /[A-Za-z_$.]/ #: Regexp
      IDENTIFIER_CONTINUE = /[A-Za-z0-9_$.-]/ #: Regexp

      # @rbs (String source, start_line: Integer, max_tokens: Integer) -> void
      def initialize(source, start_line:, max_tokens:)
        @source = source
        @index = 0
        @line = start_line
        @column = 1
        @max_tokens = max_tokens
      end

      # @rbs () -> Array[Token]
      def tokenize
        tokens = [] #: Array[Token]
        until eof?
          skip_ignored
          break if eof?

          tokens << scan_token
          check_token_budget(tokens.length)
        end
        tokens.freeze
      end

      private

      # @rbs () -> Token
      def scan_token
        line = @line
        column = @column
        byte = current_byte || raise(Ibex::Error, "(bison-import):#{line}:#{column}: unexpected end of input")
        if identifier_start?(byte)
          Token.new(type: :symbol, value: scan_identifier, line: line, column: column)
        elsif [34, 39].include?(byte)
          Token.new(type: :literal, value: scan_quoted(byte), line: line, column: column)
        elsif byte == 123
          Token.new(type: :action, value: scan_action, line: line, column: column)
        elsif byte == 37
          Token.new(type: :directive, value: scan_directive, line: line, column: column)
        elsif byte == 60
          Token.new(type: :tag, value: scan_delimited(60, 62), line: line, column: column)
        elsif byte == 91
          Token.new(type: :tag, value: scan_delimited(91, 93), line: line, column: column)
        else
          value = byte ? byte.chr : ""
          advance
          Token.new(type: punctuation_type(value), value: value, line: line, column: column)
        end
      end

      # @rbs () -> void
      def skip_ignored
        loop do
          advance while whitespace?(current_byte)
          if current_byte == 47 && peek_byte == 42
            skip_block_comment
          elsif (current_byte == 47 && peek_byte == 47) || current_byte == 35
            skip_line
          else
            break
          end
        end
      end

      # @rbs () -> String
      def scan_identifier
        start = @index
        advance while identifier_continue?(current_byte)
        @source.byteslice(start, @index - start) || ""
      end

      # @rbs () -> String
      def scan_directive
        start = @index
        advance
        advance if current_byte == 37
        advance while identifier_continue?(current_byte)
        @source.byteslice(start, @index - start) || ""
      end

      # @rbs (Integer quote) -> String
      def scan_quoted(quote)
        start = @index
        advance
        until eof?
          byte = current_byte
          advance
          if byte == 92
            advance unless eof?
          elsif byte == quote
            break
          end
        end
        @source.byteslice(start, @index - start) || ""
      end

      # @rbs () -> String
      def scan_action
        advance
        start = @index
        depth = 1
        until eof?
          byte = current_byte
          if skip_action_opaque?(byte)
            next
          elsif byte == 123
            depth += 1
            advance
          elsif byte == 125
            depth -= 1
            if depth.zero?
              value = @source.byteslice(start, @index - start) || ""
              advance
              return value
            end
            advance
          else
            advance
          end
        end
        raise Ibex::Error, "(bison-import):#{@line}:#{@column}: unterminated C action"
      end

      # @rbs (Integer? byte) -> bool
      def skip_action_opaque?(byte)
        if byte && [34, 39].include?(byte)
          scan_quoted(byte)
        elsif byte == 47 && peek_byte == 42
          skip_block_comment
        elsif byte == 47 && peek_byte == 47
          skip_line
        else
          return false
        end
        true
      end

      # @rbs (Integer opener, Integer closer) -> String
      def scan_delimited(opener, closer)
        start = @index
        advance
        until eof? || current_byte == closer
          current_byte == 92 ? 2.times { advance unless eof? } : advance
        end
        advance if current_byte == closer
        value = @source.byteslice(start, @index - start) || ""
        return value if value.getbyte(0) == opener

        ""
      end

      # @rbs () -> void
      def skip_block_comment
        advance
        advance
        until eof?
          if current_byte == 42 && peek_byte == 47
            advance
            advance
            return
          end
          advance
        end
      end

      # @rbs () -> void
      def skip_line
        advance until eof? || current_byte == 10
        advance if current_byte == 10
      end

      # @rbs (String value) -> Symbol
      def punctuation_type(value)
        case value
        when ":" then :colon
        when "|" then :pipe
        when ";" then :semicolon
        else :other
        end
      end

      # @rbs (Integer? byte) -> bool
      def identifier_start?(byte)
        byte ? IDENTIFIER_START.match?(byte.chr) : false
      end

      # @rbs (Integer? byte) -> bool
      def identifier_continue?(byte)
        byte ? IDENTIFIER_CONTINUE.match?(byte.chr) : false
      end

      # @rbs (Integer? byte) -> bool
      def whitespace?(byte)
        !byte.nil? && [9, 10, 11, 12, 13, 32].include?(byte)
      end

      # @rbs (Integer count) -> void
      def check_token_budget(count)
        return if count <= @max_tokens

        raise BudgetExceeded.new(
          result: "budget_exhausted", phase: "tokenization", max_tokens: @max_tokens
        )
      end

      # @rbs () -> Integer?
      def current_byte
        @source.getbyte(@index)
      end

      # @rbs () -> Integer?
      def peek_byte
        @source.getbyte(@index + 1)
      end

      # @rbs () -> bool
      def eof?
        @index >= @source.bytesize
      end

      # @rbs () -> void
      def advance
        return if eof?

        if current_byte == 10
          @line += 1
          @column = 1
        else
          @column += 1
        end
        @index += 1
      end
    end
  end
end
