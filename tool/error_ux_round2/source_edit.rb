# frozen_string_literal: true

module Ibex
  module ErrorUXRound2
    # Applies non-overlapping corpus byte edits against the original input.
    module SourceEdit
      module_function

      def apply(input, operations, case_id:)
        ordered = operations.sort_by { |operation| -operation.fetch("start_byte") }
        validate!(input, ordered, case_id: case_id)

        source = input.dup
        ordered.each do |operation|
          start_byte = operation.fetch("start_byte")
          end_byte = operation.fetch("end_byte")
          prefix = source.byteslice(0, start_byte)
          suffix = source.byteslice(end_byte, source.bytesize - end_byte)
          source = prefix + operation.fetch("replacement") + suffix
        end
        source
      end

      def original_offset(edited_offset, operations)
        delta = 0
        operations.sort_by { |operation| operation.fetch("start_byte") }.each do |operation|
          start_byte = operation.fetch("start_byte")
          end_byte = operation.fetch("end_byte")
          replacement_bytes = operation.fetch("replacement").bytesize
          edited_start = start_byte + delta
          edited_end = edited_start + replacement_bytes
          return edited_offset - delta if edited_offset < edited_start
          return end_byte if replacement_bytes.zero? && edited_offset == edited_start
          return start_byte if edited_offset < edited_end
          return end_byte if edited_offset == edited_end

          delta += replacement_bytes - (end_byte - start_byte)
        end
        edited_offset - delta
      end

      def validate!(input, ordered, case_id:)
        raise "#{case_id}: input has invalid encoding" unless input.valid_encoding?

        previous_start = input.bytesize + 1
        ordered.each do |operation|
          start_byte = operation.fetch("start_byte")
          end_byte = operation.fetch("end_byte")
          replacement = operation.fetch("replacement")
          unless start_byte.between?(0, input.bytesize) && end_byte.between?(start_byte, input.bytesize)
            raise "#{case_id}: proposed edit is outside the input"
          end
          raise "#{case_id}: proposed edits overlap" if end_byte > previous_start
          unless character_boundary?(input, start_byte) && character_boundary?(input, end_byte)
            raise "#{case_id}: proposed edit splits an encoded character"
          end
          raise "#{case_id}: replacement has invalid encoding" unless replacement.valid_encoding?

          previous_start = start_byte
        end
      end

      def character_boundary?(source, offset)
        source.byteslice(0, offset).valid_encoding? &&
          source.byteslice(offset, source.bytesize - offset).valid_encoding?
      end
    end
  end
end
