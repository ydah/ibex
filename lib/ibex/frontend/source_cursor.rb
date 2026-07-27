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
      :span, #: SourceSpan?
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
      attr_reader :byte_offset #: Integer
      attr_reader :line #: Integer
      attr_reader :column #: Integer

      # @rbs (String source, String file) -> void
      def initialize(source, file)
        @source = SourceEncoding.validated_utf8(source, file)
        @file = file.dup.freeze
        @character_offsets = @source.ascii_only? ? nil : build_character_offsets #: Array[Integer]?
        @character_length = @character_offsets ? @character_offsets.length - 1 : @source.bytesize
        @index = 0
        @byte_offset = 0
        @line = 1
        @column = 1
      end

      # @rbs () -> bool
      def eof?
        @index >= @character_length
      end

      # @rbs (?Integer offset) -> String?
      def peek(offset = 0)
        character_index = @index + offset
        offsets = @character_offsets
        unless offsets
          return if character_index >= @character_length

          return @source.byteslice(character_index, 1)
        end

        character_index += @character_length if character_index.negative?
        return if character_index.negative? || character_index >= @character_length

        start_byte = offsets.fetch(character_index)
        end_byte = offsets.fetch(character_index + 1)
        @source.byteslice(start_byte, end_byte - start_byte)
      end

      # @rbs () -> String
      def rest
        @source.byteslice(@byte_offset, @source.bytesize - @byte_offset) ||
          String.new(encoding: Encoding::UTF_8)
      end

      # @rbs () -> Location
      def location
        Location.new(file: @file, line: @line, column: @column)
      end

      # @rbs () -> SourcePosition
      def position
        SourcePosition.new(byte_offset: @byte_offset, line: @line, column: @column)
      end

      # @rbs (SourcePosition start) -> SourceSpan
      def span_from(start)
        SourceSpan.new(file: @file, start: start, finish: position)
      end

      # @rbs (?Integer count) -> void
      def advance(count = 1)
        return advance_with_offsets(count) if @character_offsets

        advance_ascii(count)
      end

      private

      # @rbs (Integer count) -> void
      def advance_ascii(count)
        count.times do
          break if @index >= @character_length

          newline = @source.getbyte(@index) == 10
          @index += 1
          @byte_offset = @index
          if newline
            @line += 1
            @column = 1
          else
            @column += 1
          end
        end
      end

      # @rbs (Integer count) -> void
      def advance_with_offsets(count)
        offsets = @character_offsets
        count.times do
          break if @index >= @character_length

          newline = @source.getbyte(@byte_offset) == 10
          @index += 1
          @byte_offset = offsets.fetch(@index)
          if newline
            @line += 1
            @column = 1
          else
            @column += 1
          end
        end
      end

      # @rbs () -> Array[Integer]
      def build_character_offsets
        offsets = [0]
        byte_offset = 0
        while byte_offset < @source.bytesize
          leading_byte = @source.getbyte(byte_offset)
          raise Ibex::Error, "#{@file}: input must be valid UTF-8" unless leading_byte

          byte_offset += if leading_byte < 0x80
                           1
                         elsif leading_byte < 0xE0
                           2
                         elsif leading_byte < 0xF0
                           3
                         else
                           4
                         end
          offsets << byte_offset
        end
        offsets.freeze
      end
    end
  end
end
