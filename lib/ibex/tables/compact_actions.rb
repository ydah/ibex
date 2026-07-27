# frozen_string_literal: true
# rbs_inline: enabled

require_relative "compact" unless defined?(Ibex::Tables::Compact)

module Ibex
  module Tables
    # Compact action table with an integer-coded hot representation and a
    # compatible decoded lookup surface for the generic runtime.
    class CompactActions < Compact
      ACCEPT_CODE = 0 #: Integer
      ERROR_CODE = 1 #: Integer
      SHIFT_BASE = 2 #: Integer
      REDUCE_BASE = 3 #: Integer

      attr_reader :codes #: Array[Integer?]

      class << self
        # @rbs (Array[Hash[Integer, untyped]] rows) -> CompactActions
        def build(rows)
          packed_rows = rows.map do |row|
            row.transform_values { |action| pack(action) }
          end
          layout = Compact.build(packed_rows)
          new(
            offsets: layout.offsets,
            codes: layout.values,
            checks: layout.checks,
            row_count: layout.row_count
          )
        end

        # @rbs (String offsets, String codes, String checks, row_count: Integer) -> CompactActions
        def packed(offsets, codes, checks, row_count:)
          new(
            offsets: PackedIntegers.decode_required(offsets),
            codes: PackedIntegers.decode(codes),
            checks: PackedIntegers.decode(checks),
            row_count: row_count
          )
        end

        # @rbs (untyped action) -> Integer?
        def pack(action)
          return unless action

          case action.fetch(0)
          when :accept then ACCEPT_CODE
          when :error then ERROR_CODE
          when :shift then SHIFT_BASE + (action.fetch(1) * 2)
          when :reduce then REDUCE_BASE + (action.fetch(1) * 2)
          else raise ArgumentError, "unknown compact parser action #{action.inspect}"
          end
        end

        # @rbs (Integer? code) -> untyped
        def unpack(code)
          return unless code
          return [:accept].freeze if code == ACCEPT_CODE
          return [:error].freeze if code == ERROR_CODE
          return [:shift, (code - SHIFT_BASE) / 2].freeze if code.even?

          [:reduce, (code - REDUCE_BASE) / 2].freeze
        end
      end

      # @rbs (offsets: Array[Integer], codes: Array[Integer?], checks: Array[Integer?],
      #   row_count: Integer) -> void
      def initialize(offsets:, codes:, checks:, row_count:)
        @codes = codes.freeze
        decoded_cache = {} #: Hash[Integer, untyped]
        decoded = codes.map do |code|
          code.nil? ? nil : decoded_cache[code] ||= self.class.unpack(code)
        end
        super(offsets: offsets, values: decoded, checks: checks, row_count: row_count)
      end
    end
  end
end
