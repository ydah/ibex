# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Immutable byte-oriented source with lazy line/column conversion.
      class SourceText
        # @rbs! type position = [Integer, Integer]

        attr_reader :text #: String
        attr_reader :file #: String?

        # @rbs (String text, ?file: String?) -> void
        def initialize(text, file: nil)
          @text = text.b.freeze
          @file = file&.dup&.freeze
          @line_starts = build_line_starts.freeze #: Array[Integer]
          freeze
        end

        # @rbs () -> Integer
        def bytesize = @text.bytesize

        # Apply non-overlapping byte edits expressed against this source.
        # @rbs (Array[TextEdit] edits) -> SourceText
        def apply(edits)
          ordered = edits.sort_by(&:start)
          output = String.new(encoding: Encoding::BINARY)
          cursor = 0
          ordered.each do |edit|
            raise ArgumentError, "text edits overlap" if edit.start < cursor
            raise RangeError, "text edit exceeds source" if edit.range.end > @text.bytesize

            output << (@text.byteslice(cursor, edit.start - cursor) || "".b)
            output << edit.insert_text
            cursor = edit.range.end
          end
          output << (@text.byteslice(cursor, @text.bytesize - cursor) || "".b)
          SourceText.new(output, file: @file)
        end

        # Return one-based line and Unicode-scalar column for a byte offset.
        # Invalid UTF-8 bytes count as one replacement scalar each.
        # @rbs (Integer offset) -> position
        def position(offset)
          validate_offset(offset)
          line_index = @line_starts.bsearch_index { |start| start > offset }
          line_index = line_index ? line_index - 1 : @line_starts.length - 1
          line_start = @line_starts.fetch(line_index)
          prefix = @text.byteslice(line_start, offset - line_start) || "".b
          value = [line_index + 1, unicode_scalar_length(prefix) + 1] #: position
          value.freeze
        end

        # @rbs (Range[Integer] range) -> Ibex::Location
        def location(range)
          start_offset, end_offset = normalized_range(range)
          line, column = position(start_offset)
          end_line, end_column = position(end_offset)
          Ibex::Location.new(
            file: @file, line: line, column: column, end_line: end_line, end_column: end_column,
            start_byte: start_offset, end_byte: end_offset, source_line: line_text(line)
          )
        end

        # @rbs (Integer line) -> String
        def line_text(line)
          raise ArgumentError, "line must be positive" unless line.positive?

          start_offset = @line_starts.fetch(line - 1)
          end_offset = @line_starts.fetch(line, @text.bytesize)
          value = @text.byteslice(start_offset, end_offset - start_offset) || "".b
          value.delete_suffix("\n".b).delete_suffix("\r".b)
        end

        private

        # @rbs () -> Array[Integer]
        def build_line_starts
          starts = [0]
          @text.bytes.each_with_index { |byte, index| starts << (index + 1) if byte == 10 }
          starts
        end

        # @rbs (Integer offset) -> void
        def validate_offset(offset)
          return if offset.between?(0, @text.bytesize)

          raise RangeError, "source offset #{offset} is outside 0..#{@text.bytesize}"
        end

        # @rbs (Range[Integer] range) -> position
        def normalized_range(range)
          start_offset = range.begin
          end_offset = range.end + (range.exclude_end? ? 0 : 1)
          validate_offset(start_offset)
          validate_offset(end_offset)
          raise RangeError, "range end precedes start" if end_offset < start_offset

          value = [start_offset, end_offset] #: position
          value.freeze
        end

        # @rbs (String bytes) -> Integer
        def unicode_scalar_length(bytes)
          bytes.dup.force_encoding(Encoding::UTF_8).scrub.length
        end
      end
    end
  end
end
