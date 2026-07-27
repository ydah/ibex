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
            row_count: layout.row_count,
            encoding: :signed
          )
        end

        # @rbs (String offsets, String codes, String checks, row_count: Integer,
        #   ?encoding: Symbol) -> CompactActions
        def packed(offsets, codes, checks, row_count:, encoding: :legacy)
          new(
            offsets: PackedIntegers.decode_required(offsets),
            codes: encoding == :signed ? PackedIntegers.decode_signed(codes) : PackedIntegers.decode(codes),
            checks: PackedIntegers.decode(checks),
            row_count: row_count,
            encoding: encoding
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
      #   row_count: Integer, ?encoding: Symbol) -> void
      def initialize(offsets:, codes:, checks:, row_count:, encoding: :legacy)
        codes = codes.map { |code| self.class.legacy_to_signed(code) } if encoding == :legacy
        unless %i[legacy signed].include?(encoding)
          raise ArgumentError, "unknown compact action encoding #{encoding.inspect}"
        end

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
