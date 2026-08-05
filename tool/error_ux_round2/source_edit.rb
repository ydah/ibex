# frozen_string_literal: true

module Ibex
  module ErrorUXRound2
    # Applies non-overlapping corpus byte edits against the original input.
    module SourceEdit
      module_function

      def apply(input, operations, case_id:)
        source = input.dup
        ordered = operations.sort_by { |operation| -operation.fetch("start_byte") }
        previous_start = source.bytesize + 1
        ordered.each do |operation|
          start_byte = operation.fetch("start_byte")
          end_byte = operation.fetch("end_byte")
          unless start_byte.between?(0, source.bytesize) && end_byte.between?(start_byte, source.bytesize)
            raise "#{case_id}: proposed edit is outside the input"
          end
          raise "#{case_id}: proposed edits overlap" if end_byte > previous_start

          source[start_byte...end_byte] = operation.fetch("replacement")
          previous_start = start_byte
        end
        source
      end
    end
  end
end
