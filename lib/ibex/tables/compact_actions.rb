# frozen_string_literal: true
# rbs_inline: enabled

require_relative "compact" unless defined?(Ibex::Tables::Compact)

module Ibex
  module Tables
    # Compact action table with an integer-coded hot representation and a
    # compatible decoded lookup surface for the generic runtime.
    class CompactActions < Compact
      ACCEPT_CODE = 0 #: Integer
      ERROR_CODE = -1 #: Integer
      SHIFT_BASE = 1 #: Integer
      REDUCE_BASE = -2 #: Integer
      LEGACY_ERROR_CODE = 1 #: Integer
      LEGACY_SHIFT_BASE = 2 #: Integer
      LEGACY_REDUCE_BASE = 3 #: Integer
      private_constant :LEGACY_ERROR_CODE, :LEGACY_SHIFT_BASE, :LEGACY_REDUCE_BASE

      attr_reader :codes #: Array[Integer?]
      attr_reader :dense_codes #: Array[Integer?]?
      attr_reader :column_count #: Integer?

      class << self
        # @rbs (Array[Hash[Integer, untyped]] rows) -> CompactActions
        def build(rows)
          packed_rows = rows.map do |row|
            row.transform_values { |action| pack(action) }
          end
          layout = Compact.build(packed_rows, dense: false)
          column_count = rows.flat_map(&:keys).max.to_i + 1
          column_count = nil if (rows.length * column_count) > Compact::DENSE_CELL_LIMIT
          new(
            offsets: layout.offsets,
            codes: layout.values,
            checks: layout.checks,
            row_count: layout.row_count,
            encoding: :signed,
            column_count: column_count
          )
        end

        # @rbs (String offsets, String codes, String checks, row_count: Integer,
        #   ?encoding: Symbol, ?column_count: Integer?) -> CompactActions
        def packed(offsets, codes, checks, row_count:, encoding: :legacy, column_count: nil)
          new(
            offsets: PackedIntegers.decode_required(offsets),
            codes: encoding == :signed ? PackedIntegers.decode_signed(codes) : PackedIntegers.decode(codes),
            checks: PackedIntegers.decode(checks),
            row_count: row_count,
            encoding: encoding,
            column_count: column_count
          )
        end

        # @rbs (untyped action) -> Integer?
        def pack(action)
          return unless action

          case action.fetch(0)
          when :accept then ACCEPT_CODE
          when :error then ERROR_CODE
          when :shift then SHIFT_BASE + action.fetch(1)
          when :reduce then REDUCE_BASE - action.fetch(1)
          else raise ArgumentError, "unknown compact parser action #{action.inspect}"
          end
        end

        # @rbs (Integer? code) -> untyped
        def unpack(code)
          return unless code
          return [:accept].freeze if code == ACCEPT_CODE
          return [:error].freeze if code == ERROR_CODE
          return [:shift, code - SHIFT_BASE].freeze if code.positive?

          [:reduce, REDUCE_BASE - code].freeze
        end

        # Convert codes emitted before signed compact actions without changing
        # their generated table literals.
        # @rbs (Integer? code) -> Integer?
        def legacy_to_signed(code)
          return unless code
          return ACCEPT_CODE if code == ACCEPT_CODE
          return ERROR_CODE if code == LEGACY_ERROR_CODE
          return SHIFT_BASE + ((code - LEGACY_SHIFT_BASE) / 2) if code.even?

          REDUCE_BASE - ((code - LEGACY_REDUCE_BASE) / 2)
        end
      end

      # @rbs (offsets: Array[Integer], codes: Array[Integer?], checks: Array[Integer?],
      #   row_count: Integer, ?encoding: Symbol, ?column_count: Integer?) -> void
      def initialize(offsets:, codes:, checks:, row_count:, encoding: :legacy, column_count: nil)
        codes = codes.map { |code| self.class.legacy_to_signed(code) } if encoding == :legacy
        unless %i[legacy signed].include?(encoding)
          raise ArgumentError, "unknown compact action encoding #{encoding.inspect}"
        end

        @codes = codes.freeze
        @column_count = column_count
        @dense_codes = dense_action_layout(offsets, codes, checks, row_count, column_count)
        decoded_cache = {} #: Hash[Integer, untyped]
        decoded = codes.map do |code|
          code.nil? ? nil : decoded_cache[code] ||= self.class.unpack(code)
        end
        super(offsets: offsets, values: decoded, checks: checks, row_count: row_count)
      end

      # @rbs (Integer row) -> Hash[Integer, IR::runtime_action]
      def row(row)
        super #: Hash[Integer, IR::runtime_action]
      end

      private

      # @rbs (Array[Integer] offsets, Array[Integer?] codes, Array[Integer?] checks,
      #   Integer row_count, Integer? column_count) -> Array[Integer?]?
      def dense_action_layout(offsets, codes, checks, row_count, column_count)
        return nil unless column_count
        raise ArgumentError, "compact action column count must be positive" unless column_count.positive?

        return nil if (row_count * column_count) > Compact::DENSE_CELL_LIMIT

        dense = Array.new(row_count * column_count) #: Array[Integer?]
        checks.each_index do |index|
          row = checks[index]
          next unless row

          column = index - offsets.fetch(row)
          raise ArgumentError, "compact action column exceeds the dense row width" unless
            column.between?(0, column_count - 1)

          dense[(row * column_count) + column] = codes[index]
        end
        dense.freeze
      end
    end
  end
end
