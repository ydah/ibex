# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Tables
    # Sparse table represented by per-row offsets and ownership checks.
    class Compact
      attr_reader :offsets #: Array[Integer]
      attr_reader :values #: Array[untyped]
      attr_reader :checks #: Array[Integer?]
      attr_reader :row_count #: Integer

      class << self
        # @rbs (Array[Hash[Integer, untyped]] rows) -> Compact
        def build(rows)
          offsets = Array.new(rows.length, 0)
          values = [] #: Array[untyped]
          checks = [] #: Array[Integer?]
          next_offsets = {} #: Hash[Array[Integer], Integer]
          rows.each_index.sort_by { |row| [-rows[row].length, row] }.each do |row|
            offset = find_offset(rows[row].keys, checks, next_offsets)
            offsets[row] = offset
            rows[row].each do |column, value|
              index = offset + column
              values[index] = value
              checks[index] = row
            end
          end
          new(offsets: offsets, values: values, checks: checks, row_count: rows.length)
        end

        private

        # @rbs (Array[Integer] columns, Array[Integer?] checks, Hash[Array[Integer], Integer] next_offsets) -> Integer
        def find_offset(columns, checks, next_offsets)
          return 0 if columns.empty?

          signature = columns.sort
          offset = next_offsets.fetch(signature, 0)
          offset += 1 while columns.any? { |column| checks[offset + column] }
          next_offsets[signature] = offset + 1
          offset
        end
      end

      # @rbs (offsets: Array[Integer], values: Array[untyped], checks: Array[Integer?], row_count: Integer) -> void
      def initialize(offsets:, values:, checks:, row_count:)
        @offsets = offsets.freeze
        @values = values.freeze
        @checks = checks.freeze
        @row_count = row_count
        freeze
      end

      # @rbs (Integer row, Integer column) -> untyped
      def lookup(row, column)
        return nil unless row.between?(0, @row_count - 1)
        return nil if column.negative?

        index = @offsets.fetch(row) + column
        return nil unless index.between?(0, @checks.length - 1)

        @checks[index] == row ? @values[index] : nil
      end

      # @rbs (Integer row) -> Hash[Integer, untyped]
      def row(row)
        return {} unless row.between?(0, @row_count - 1)

        result = {} #: Hash[Integer, untyped]
        @checks.each_index do |index|
          next unless @checks[index] == row

          result[index - @offsets[row]] = @values[index]
        end
        result
      end
    end
  end
end
