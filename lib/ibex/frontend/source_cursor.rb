# frozen_string_literal: true

module Ibex
  module Frontend
    # A source coordinate retained by frontend and IR objects.
    Location = Struct.new(
      :file, #: String
      :line, #: Integer
      :column, #: Integer
      keyword_init: true
    )

    class Location
      # @rbs () -> IR::location
      def to_h
        { file: file, line: line, column: column }
      end

      # @rbs () -> String
      def to_s
        "#{file}:#{line}:#{column}"
      end
    end

    # A grammar token and its source coordinate.
    Token = Struct.new(
      :type, #: Symbol
      :value, #: token_value
      :location, #: Location
      keyword_init: true
    )

    class Token
      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { type: type, value: value, location: location.to_h }
      end
    end

    # Advances through source text while maintaining one-based coordinates.
    class SourceCursor
      attr_reader :source #: String
      attr_reader :file #: String
      attr_reader :index #: Integer
      attr_reader :line #: Integer
      attr_reader :column #: Integer

      # @rbs (String source, String file) -> void
      def initialize(source, file)
        @source = source
        @file = file
        @index = 0
        @line = 1
        @column = 1
      end

      # @rbs () -> bool
      def eof?
        @index >= @source.length
      end

      # @rbs (?Integer offset) -> String?
      def peek(offset = 0)
        @source[@index + offset]
      end

      # @rbs () -> String
      def rest
        @source[@index..] || ""
      end

      # @rbs () -> Location
      def location
        Location.new(file: @file, line: @line, column: @column)
      end

      # @rbs (?Integer count) -> void
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
