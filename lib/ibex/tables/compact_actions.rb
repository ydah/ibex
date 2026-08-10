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

      attr_reader :codes #: Array[Integer?]
      attr_reader :dense_codes #: Array[Integer?]?
      attr_reader :column_count #: Integer?

      class << self
        # @rbs (Array[Hash[Integer, IR::runtime_action]] rows) -> CompactActions
        def build(rows)
          packed_rows = rows.map do |row|
            row.transform_values { |action| pack(action) }
          end
          layout = Compact.build(packed_rows, dense: false)
          codes = layout.values #: Array[Integer?]
          column_count = rows.flat_map(&:keys).max.to_i + 1
          column_count = nil if (rows.length * column_count) > Compact::DENSE_CELL_LIMIT
          new(
            offsets: layout.offsets,
            codes: codes,
            checks: layout.checks,
            row_count: layout.row_count,
            encoding: :signed,
            column_count: column_count
          )
        end

        # @rbs (String offsets, String codes, String checks, row_count: Integer,
        #   ?encoding: Symbol, ?column_count: Integer?) -> CompactActions
        def packed(offsets, codes, checks, row_count:, encoding: :signed, column_count: nil)
          unless encoding == :signed
            raise ArgumentError, "unknown compact action encoding #{encoding.inspect}; expected :signed"
          end

          new(
            offsets: PackedIntegers.decode_required(offsets),
            codes: PackedIntegers.decode_signed(codes),
            checks: PackedIntegers.decode(checks),
            row_count: row_count,
            encoding: encoding,
            column_count: column_count
          )
        end

        # @rbs (IR::runtime_action? action) -> Integer?
        def pack(action)
          return unless action

          case action.fetch(0)
          when :accept then ACCEPT_CODE
          when :error then ERROR_CODE
          when :shift
            state = action.fetch(1) #: Integer
            SHIFT_BASE + state
          when :reduce
            production = action.fetch(1) #: Integer
            REDUCE_BASE - production
          else raise ArgumentError, "unknown compact parser action #{action.inspect}"
          end
        end

        # @rbs (Integer? code) -> IR::runtime_action?
        def unpack(code)
          return unless code

          if code == ACCEPT_CODE
            accept = [:accept].freeze #: [:accept]
            return accept
          end
          if code == ERROR_CODE
            error = [:error].freeze #: [:error]
            return error
          end
          if code.positive?
            shift = [:shift, code - SHIFT_BASE].freeze #: [:shift, Integer]
            return shift
          end

          [:reduce, REDUCE_BASE - code].freeze #: [:reduce, Integer]
        end
      end

      # @rbs (offsets: Array[Integer], codes: Array[Integer?], checks: Array[Integer?],
      #   row_count: Integer, ?encoding: Symbol, ?column_count: Integer?) -> void
      def initialize(offsets:, codes:, checks:, row_count:, encoding: :signed, column_count: nil)
        unless encoding == :signed
          raise ArgumentError, "unknown compact action encoding #{encoding.inspect}; expected :signed"
        end

        @codes = codes.freeze
        @column_count = column_count
        @dense_codes = dense_action_layout(offsets, codes, checks, row_count, column_count)
        decoded_cache = {} #: Hash[Integer, IR::runtime_action]
        decoded = codes.map do |code|
          next unless code

          unpacked = self.class.unpack(code) #: IR::runtime_action
          decoded_cache[code] ||= unpacked
        end
        super(offsets: offsets, values: decoded, checks: checks, row_count: row_count)
      end

      # @rbs (Integer row) -> Hash[Integer, IR::runtime_action]
      # rubocop:disable Lint/UselessMethodDefinition -- narrows the inherited row contract for typed parser actions.
      def row(row)
        super #: Hash[Integer, IR::runtime_action]
      end
      # rubocop:enable Lint/UselessMethodDefinition

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
