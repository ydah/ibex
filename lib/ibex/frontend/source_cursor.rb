# frozen_string_literal: true

module Ibex
  module Frontend
    # A source coordinate retained by frontend and IR objects.
    Location = Struct.new(:file, :line, :column, keyword_init: true)

    class Location
      def to_h
        { file: file, line: line, column: column }
      end

      def to_s
        "#{file}:#{line}:#{column}"
      end
    end

    # A grammar token and its source coordinate.
    Token = Struct.new(:type, :value, :location, keyword_init: true)

    class Token
      def to_h
        { type: type, value: value, location: location.to_h }
      end
    end

    # Advances through source text while maintaining one-based coordinates.
    class SourceCursor
      attr_reader :source, :file, :index, :line, :column

      def initialize(source, file)
        @source = source
        @file = file
        @index = 0
        @line = 1
        @column = 1
      end

      def eof?
        @index >= @source.length
      end

      def peek(offset = 0)
        @source[@index + offset]
      end

      def rest
        @source[@index..] || ""
      end

      def location
        Location.new(file: @file, line: @line, column: @column)
      end

      def advance(count = 1)
        count.times do
          character = @source[@index]
          break unless character

          @index += 1
          if character == "\n"
            @line += 1
            @column = 1
          else
            @column += 1
          end
        end
      end
    end
  end
end
