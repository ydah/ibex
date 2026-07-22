# frozen_string_literal: true

module Ibex
  module Frontend
    # Extracts a balanced Ruby action while ignoring braces inside literals.
    class ActionScanner
      # @rbs!
      #   type heredoc = {
      #     identifier: String,
      #     indented: bool,
      #     length: Integer,
      #     location: Location
      #   }

      PAIRED_DELIMITERS = { "(" => ")", "[" => "]", "{" => "}", "<" => ">" }.freeze
      REGEX_PREFIXES = "=([{!,:;?&|+-*%^~<>"

      # @rbs @cursor: SourceCursor
      # @rbs @pending_heredocs: Array[heredoc]

      # @rbs (SourceCursor cursor) -> void
      def initialize(cursor)
        @cursor = cursor
        @pending_heredocs = [] #: Array[heredoc]
      end

      # @rbs () -> Token
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

      # @rbs (Integer depth) -> void
      def scan_code(depth)
        until @cursor.eof?
          if @cursor.peek == "\n" && @pending_heredocs.any?
            @cursor.advance
            scan_pending_heredocs
            next
          end

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

      # @rbs () -> void
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

      # @rbs (String quote) -> void
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

      # @rbs () -> void
      def scan_interpolation
        depth = 1
        until @cursor.eof?
          character = @cursor.peek
          raise Ibex::Error, "#{@cursor.location}: unterminated string interpolation" unless character

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

      # @rbs () -> void
      def scan_percent_literal
        match = @cursor.rest.match(/\A%(?:[qQwWiIxrs])?([^\w\s])/)
        return unless match

        literal_prefix = match[0]
        opener = match[1]
        return unless literal_prefix && opener

        closer = PAIRED_DELIMITERS.fetch(opener, opener)
        @cursor.advance(literal_prefix.length)
        scan_delimited(opener, closer)
      end

      # @rbs (String opener, String closer) -> void
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

      # @rbs () -> bool
      def regexp_start?
        prefix = @cursor.source.chars.take(@cursor.index).join.rstrip[-1]
        prefix.nil? || REGEX_PREFIXES.include?(prefix)
      end

      # @rbs () -> void
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

      # @rbs () -> void
      def scan_comment
        @cursor.advance until @cursor.eof? || @cursor.peek == "\n"
      end

      # @rbs () -> void
      def scan_character_literal
        @cursor.advance
        @cursor.advance if @cursor.peek == "\\"
        @cursor.advance unless @cursor.eof?
      end

      # @rbs () -> void
      def scan_heredoc
        opener = heredoc_opener
        return unless opener

        @cursor.advance(opener[:length])
        @pending_heredocs << opener
      end

      # @rbs () -> heredoc?
      def heredoc_opener
        prefix = @cursor.rest.match(/\A<<([~-]?)/)
        return unless prefix

        marker = prefix[0]
        return unless marker

        quote = @cursor.rest[marker.length]
        identifier, length = if quote && ["'", '"', "`"].include?(quote)
                               quoted_heredoc_identifier(marker, quote)
                             else
                               bare_heredoc_identifier(marker)
                             end
        return unless identifier

        modifier = prefix[1] || ""
        { identifier: identifier, indented: !modifier.empty?, length: length,
          location: @cursor.location } #: heredoc
      end

      # @rbs (String prefix, String quote) -> [String, Integer]?
      def quoted_heredoc_identifier(prefix, quote)
        start = prefix.length + 1
        finish = @cursor.rest.index(quote, start)
        return unless finish

        identifier = @cursor.rest[start...finish]
        return unless identifier
        return if identifier.match?(/[\r\n]/)

        [identifier, finish + 1]
      end

      # @rbs (String prefix) -> [String?, Integer]
      def bare_heredoc_identifier(prefix)
        suffix = @cursor.rest[prefix.length..] || ""
        identifier = suffix.match(/\A[A-Za-z_]\w*/)&.[](0)
        [identifier, prefix.length + identifier.to_s.length]
      end

      # @rbs () -> void
      def scan_pending_heredocs
        @pending_heredocs.shift.then { |heredoc| scan_heredoc_body(heredoc) } until @pending_heredocs.empty?
      end

      # @rbs (heredoc heredoc) -> void
      def scan_heredoc_body(heredoc)
        identifier = heredoc[:identifier]
        escaped_identifier = Regexp.escape(identifier)
        prefix = heredoc[:indented] ? "[ \\t]*" : ""
        terminator = /\A#{prefix}#{escaped_identifier}\r?\z/
        until @cursor.eof?
          line = @cursor.rest[/\A[^\n]*(?:\n|\z)/] || ""
          content = line.delete_suffix("\n")
          @cursor.advance(line.length)
          return if content.match?(terminator)
        end
        raise Ibex::Error, "#{heredoc[:location]}: unterminated heredoc #{identifier}"
      end
    end
  end
end
