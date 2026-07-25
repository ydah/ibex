# frozen_string_literal: true

module Ibex
  module LSP
    # Converts between frontend byte offsets and zero-based LSP UTF-16 positions.
    class PositionCodec
      # @rbs (String source) -> void
      def initialize(source)
        @source = Frontend::SourceEncoding.validated_utf8(source, "(lsp)")
        @line_starts = build_line_starts.freeze #: Array[Integer]
      end

      # @rbs (Integer byte_offset) -> Hash[String, Integer]
      def position(byte_offset)
        validate_byte_offset(byte_offset)
        prefix = @source.byteslice(0, byte_offset) || ""
        raise ArgumentError, "byte offset is not on a UTF-8 character boundary" unless prefix.valid_encoding?

        line = (@line_starts.bsearch_index { |start| start > byte_offset } || @line_starts.length) - 1
        line_start = @line_starts.fetch(line)
        line_end = content_end(line)
        raise ArgumentError, "byte offset points inside a line ending" if byte_offset > line_end

        text = @source.byteslice(line_start, byte_offset - line_start) || ""
        { "line" => line, "character" => utf16_length(text) }
      end

      # @rbs (Hash[String, untyped] position) -> Integer
      def byte_offset(position)
        line = integer_member(position, "line")
        character = integer_member(position, "character")
        raise ArgumentError, "line and character must be non-negative" if line.negative? || character.negative?

        line_start = @line_starts[line]
        raise ArgumentError, "line is outside the document" unless line_start

        text = @source.byteslice(line_start, content_end(line) - line_start) || ""
        line_start + byte_length_at_utf16(text, character)
      end

      # @rbs (Frontend::SourceSpan span) -> Hash[String, Hash[String, Integer]]
      def range(span)
        { "start" => position(span.start_byte), "end" => position(span.end_byte) }
      end

      private

      # @rbs () -> Array[Integer]
      def build_line_starts
        starts = [0]
        offset = 0
        @source.each_char do |character|
          offset += character.bytesize
          starts << offset if character == "\n"
        end
        starts
      end

      # @rbs (Integer line) -> Integer
      def content_end(line)
        boundary = @line_starts[line + 1] || @source.bytesize
        return boundary unless @line_starts[line + 1]

        before_newline = boundary - 1
        @source.getbyte(before_newline - 1) == 13 ? before_newline - 1 : before_newline
      end

      # @rbs (String text) -> Integer
      def utf16_length(text)
        text.each_codepoint.sum { |codepoint| codepoint > 0xFFFF ? 2 : 1 }
      end

      # @rbs (String text, Integer units) -> Integer
      def byte_length_at_utf16(text, units)
        consumed_units = 0
        consumed_bytes = 0
        text.each_char do |character|
          return consumed_bytes if consumed_units == units

          width = character.ord > 0xFFFF ? 2 : 1
          if consumed_units + width > units
            raise ArgumentError, "character points into the middle of a UTF-16 surrogate pair"
          end

          consumed_units += width
          consumed_bytes += character.bytesize
        end
        return consumed_bytes if consumed_units == units

        raise ArgumentError, "character is outside the document line"
      end

      # @rbs (Hash[String, untyped] position, String name) -> Integer
      def integer_member(position, name)
        value = position[name]
        raise ArgumentError, "#{name} must be an integer" unless value.is_a?(Integer)

        value
      end

      # @rbs (Integer byte_offset) -> void
      def validate_byte_offset(byte_offset)
        return if byte_offset.is_a?(Integer) && byte_offset.between?(0, @source.bytesize)

        raise ArgumentError, "byte offset is outside the document"
      end
    end
  end
end
