# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Tables
    # Encodes nonnegative integer arrays into compact generated-source
    # literals. Zero represents nil; positive values are offset by one.
    module PackedIntegers
      # @rbs (Array[Integer?] values) -> String
      def encode(values)
        encoded = values.map do |value|
          raise ArgumentError, "packed integer must be nonnegative or nil" if value&.negative?

          value ? value + 1 : 0
        end.pack("w*")
        [encoded].pack("m0")
      end

      # @rbs (String source) -> Array[Integer?]
      def decode(source)
        binary = source.unpack1("m0")
        raise ArgumentError, "packed integer source is invalid" unless binary.is_a?(String)

        values = binary.unpack("w*") #: Array[Integer]
        values.map { |value| value.zero? ? nil : value - 1 }
      rescue ArgumentError
        raise ArgumentError, "packed integer source is invalid"
      end

      # @rbs (String source) -> Array[Integer]
      def decode_required(source)
        decode(source).map do |value|
          raise ArgumentError, "packed integer source contains nil" unless value

          value
        end
      end

      # Zigzag-encode signed values after reserving zero for nil.
      # @rbs (Array[Integer?] values) -> String
      def encode_signed(values)
        encode(
          values.map do |value|
            next unless value

            value.negative? ? (-value * 2) - 1 : value * 2
          end
        )
      end

      # @rbs (String source) -> Array[Integer?]
      def decode_signed(source)
        decode(source).map do |value|
          next unless value

          value.even? ? value / 2 : -((value + 1) / 2)
        end
      end

      module_function :encode
      module_function :decode
      module_function :decode_required
      module_function :encode_signed
      module_function :decode_signed
    end

    # Sparse table represented by per-row offsets and ownership checks.
    class Compact
      DENSE_CELL_LIMIT = 1_000_000 #: Integer

      attr_reader :offsets #: Array[Integer]
      attr_reader :values #: Array[untyped]
      attr_reader :checks #: Array[Integer?]
      attr_reader :row_count #: Integer
      attr_reader :dense_values #: Array[untyped]?
      attr_reader :dense_width #: Integer?

      class << self
        # @rbs (Array[Hash[Integer, untyped]] rows, ?dense: bool) -> Compact
        def build(rows, dense: true)
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
          dense_width = rows.flat_map(&:keys).max.to_i + 1 if dense
          dense_width = nil if dense_width && (rows.length * dense_width) > DENSE_CELL_LIMIT
          new(
            offsets: offsets, values: values, checks: checks, row_count: rows.length,
            dense_width: dense_width
          )
        end

        # @rbs (String offsets, String values, String checks, row_count: Integer,
        #   ?dense_width: Integer?) -> Compact
        def packed(offsets, values, checks, row_count:, dense_width: nil)
          new(
            offsets: PackedIntegers.decode_required(offsets),
            values: PackedIntegers.decode(values),
            checks: PackedIntegers.decode(checks),
            row_count: row_count,
            dense_width: dense_width
          )
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

      # @rbs (offsets: Array[Integer], values: Array[untyped], checks: Array[Integer?],
      #   row_count: Integer, ?dense_width: Integer?) -> void
      def initialize(offsets:, values:, checks:, row_count:, dense_width: nil)
        @offsets = offsets.freeze
        @values = values.freeze
        @checks = checks.freeze
        @row_count = row_count
        @dense_width = dense_width
        @dense_values = dense_layout(dense_width)
        freeze
      end

      # Keep predicate dispatch out of this lookup because every parser action
      # and goto crosses it.
      # rubocop:disable Style/NumericPredicate
      # @rbs (Integer row, Integer column) -> untyped
      def lookup(row, column)
        return nil if row < 0 || row >= @row_count || column < 0

        index = @offsets[row] + column
        return nil if index < 0 || index >= @checks.length

        @checks[index] == row ? @values[index] : nil
      end
      # rubocop:enable Style/NumericPredicate

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

      private

      # @rbs (Integer? dense_width) -> Array[untyped]?
      def dense_layout(dense_width)
        return nil unless dense_width
        raise ArgumentError, "compact dense width must be positive" unless dense_width.positive?
        return nil if (@row_count * dense_width) > DENSE_CELL_LIMIT

        dense = Array.new(@row_count * dense_width) #: Array[untyped]
        @checks.each_index do |index|
          row = @checks[index]
          next unless row

          column = index - @offsets.fetch(row)
          raise ArgumentError, "compact column exceeds the dense row width" unless
            column.between?(0, dense_width - 1)

          dense[(row * dense_width) + column] = @values[index]
        end
        dense.freeze
      end
    end
  end
end
