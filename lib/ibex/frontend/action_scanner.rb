# frozen_string_literal: true

module Ibex
  module Frontend
    # Extracts a balanced Ruby action while ignoring braces inside literals.
    class ActionScanner
      PAIRED_DELIMITERS = { "(" => ")", "[" => "]", "{" => "}", "<" => ">" }.freeze
      REGEX_PREFIXES = "=([{!,:;?&|+-*%^~<>"

      def initialize(cursor)
        @cursor = cursor
      end

      def scan
        location = @cursor.location
        @cursor.advance
        start = @cursor.index
        scan_code(1)
        finish = @cursor.index
        @cursor.advance
        Token.new(type: :action, value: @cursor.source[start...finish], location: location)
      rescue Ibex::Error
        raise
      rescue StandardError => e
        raise Ibex::Error, "#{location}: unable to scan action: #{e.message}"
      end

      private

      def scan_code(depth)
        until @cursor.eof?
          index = @cursor.index
          scan_special_character
          next if @cursor.index != index

          depth += 1 if @cursor.peek == "{"
          depth -= 1 if @cursor.peek == "}"
          return if depth.zero?

          @cursor.advance
        end
        raise Ibex::Error, "#{@cursor.location}: unterminated action"
      end

      def scan_special_character
        character = @cursor.peek
        case character
        when "'", '"', "`" then scan_quoted(character)
        when "%" then scan_percent_literal
        when "/" then scan_regexp if regexp_start?
        when "#" then scan_comment
        when "?" then scan_character_literal
        when "<" then scan_heredoc if @cursor.peek(1) == "<"
        end
      end

      def scan_quoted(quote)
        start = @cursor.location
        @cursor.advance
        until @cursor.eof?
          if @cursor.peek == "\\"
            @cursor.advance(2)
          elsif quote != "'" && @cursor.rest.start_with?("\#{")
            @cursor.advance(2)
            scan_interpolation
          elsif @cursor.peek == quote
            @cursor.advance
            return
          else
            @cursor.advance
          end
        end
        raise Ibex::Error, "#{start}: unterminated #{quote} string in action"
      end

      def scan_interpolation
        depth = 1
        until @cursor.eof?
          character = @cursor.peek
          if ["'", '"', "`"].include?(character)
            scan_quoted(character)
            next
          end
          if character == "{"
            depth += 1
          elsif character == "}"
            depth -= 1
            @cursor.advance
            return if depth.zero?

            next
          end
          @cursor.advance
        end
        raise Ibex::Error, "#{@cursor.location}: unterminated string interpolation"
      end

      def scan_percent_literal
        match = @cursor.rest.match(/\A%(?:[qQwWiIxrs])?([^\w\s])/)
        return unless match

        opener = match[1]
        closer = PAIRED_DELIMITERS.fetch(opener, opener)
        @cursor.advance(match[0].length)
        scan_delimited(opener, closer)
      end

      def scan_delimited(opener, closer)
        start = @cursor.location
        depth = 1
        until @cursor.eof?
          if @cursor.peek == "\\"
            @cursor.advance(2)
            next
          end
          depth += 1 if opener != closer && @cursor.peek == opener
          depth -= 1 if @cursor.peek == closer
          @cursor.advance
          return if depth.zero?
        end
        raise Ibex::Error, "#{start}: unterminated percent literal"
      end

      def regexp_start?
        prefix = @cursor.source[0...@cursor.index].rstrip[-1]
        prefix.nil? || REGEX_PREFIXES.include?(prefix)
      end

      def scan_regexp
        start = @cursor.location
        @cursor.advance
        in_class = false
        until @cursor.eof?
          if @cursor.peek == "\\"
            @cursor.advance(2)
            next
          end
          in_class = true if @cursor.peek == "["
          in_class = false if @cursor.peek == "]"
          if @cursor.peek == "/" && !in_class
            @cursor.advance
            @cursor.advance while @cursor.peek&.match?(/[a-z]/i)
            return
          end
          @cursor.advance
        end
        raise Ibex::Error, "#{start}: unterminated regular expression"
      end

      def scan_comment
        @cursor.advance until @cursor.eof? || @cursor.peek == "\n"
      end

      def scan_character_literal
        @cursor.advance
        @cursor.advance if @cursor.peek == "\\"
        @cursor.advance unless @cursor.eof?
      end

      def scan_heredoc
        unsupported = @cursor.rest.match?(/\A<<[~-]?["']/)
        raise Ibex::Error, "#{@cursor.location}: quoted heredoc identifiers are not supported" if unsupported

        match = @cursor.rest.match(/\A<<([~-]?)([A-Za-z_]\w*)[ \t]*(?:\r?\n)/)
        return unless match

        indentation, identifier = match.captures
        @cursor.advance(match[0].length)
        escaped_identifier = Regexp.escape(identifier)
        terminator = indentation.empty? ? /^#{escaped_identifier}\r?$/ : /^[ \t]*#{escaped_identifier}\r?$/
        until @cursor.eof?
          line = @cursor.rest[/\A[^\n]*(?:\n|\z)/]
          content = line.delete_suffix("\n")
          @cursor.advance(line.length)
          return if content.match?(terminator)
        end
        raise Ibex::Error, "#{@cursor.location}: unterminated heredoc #{identifier}"
      end
    end
  end
end
