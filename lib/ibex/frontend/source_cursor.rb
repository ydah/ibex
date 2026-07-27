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
        @ascii_only = @source.ascii_only?
        @character_length = @ascii_only ? @source.bytesize : @source.length
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
        if @ascii_only
          return if character_index >= @character_length

          return @source.byteslice(character_index, 1)
        end

        character_index += @character_length if character_index.negative?
        return if character_index.negative? || character_index >= @character_length

        start_byte = if character_index == @index
                       @byte_offset
                     elsif character_index == @index + 1
                       @byte_offset + utf8_character_width(@byte_offset)
                     else
                       byte_offset_for_character(character_index)
                     end
        @source.byteslice(start_byte, utf8_character_width(start_byte))
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
        return advance_utf8(count) unless @ascii_only

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
      def advance_utf8(count)
        count.times do
          break if @index >= @character_length

          leading_byte = @source.getbyte(@byte_offset)
          raise Ibex::Error, "#{@file}: input must be valid UTF-8" unless leading_byte

          @index += 1
          @byte_offset += if leading_byte < 0x80
                            1
                          elsif leading_byte < 0xE0
                            2
                          elsif leading_byte < 0xF0
                            3
                          else
                            4
                          end
          if leading_byte == 10
            @line += 1
            @column = 1
          else
            @column += 1
          end
        end
      end

      # @rbs (Integer character_index) -> Integer
      def byte_offset_for_character(character_index)
        start_distance = character_index
        current_distance = (character_index - @index).abs
        finish_distance = @character_length - character_index

        if current_distance <= start_distance && current_distance <= finish_distance
          walk_to_character(@byte_offset, @index, character_index)
        elsif start_distance <= finish_distance
          walk_to_character(0, 0, character_index)
        else
          walk_to_character(@source.bytesize, @character_length, character_index)
        end
      end

      # @rbs (Integer byte_offset, Integer from_index, Integer to_index) -> Integer
      def walk_to_character(byte_offset, from_index, to_index)
        while from_index < to_index
          byte_offset += utf8_character_width(byte_offset)
          from_index += 1
        end
        while from_index > to_index
          byte_offset = previous_character_byte_offset(byte_offset)
          from_index -= 1
        end
        byte_offset
      end

      # @rbs (Integer byte_offset) -> Integer
      def previous_character_byte_offset(byte_offset)
        byte_offset -= 1
        while (byte = @source.getbyte(byte_offset)) && continuation_byte?(byte)
          byte_offset -= 1
        end
        byte_offset
      end

      # @rbs (Integer byte_offset) -> Integer
      def utf8_character_width(byte_offset)
        leading_byte = @source.getbyte(byte_offset)
        raise Ibex::Error, "#{@file}: input must be valid UTF-8" unless leading_byte

        return 1 if leading_byte < 0x80
        return 2 if leading_byte < 0xE0
        return 3 if leading_byte < 0xF0

        4
      end

      # @rbs (Integer byte) -> bool
      def continuation_byte?(byte)
        byte >= 0x80 && byte < 0xC0
      end
    end
  end
end
