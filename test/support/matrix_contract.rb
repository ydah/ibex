# frozen_string_literal: true

require_relative "../../tool/quality/runtime_abi/reviewed_test_contract"

module Ibex
  module TestSupport
    # Closed axis vocabulary for the runtime interaction matrix.
    module MatrixContract
      AXIS_ORDER = %w[algorithm table cst locations entries].freeze
      AXIS_VALUES = Ibex::Quality::RuntimeABIReviewedTestContract::AXES

      def self.validate_axes!(axes)
        raise ArgumentError, "matrix axes must be a mapping" unless axes.is_a?(Hash)

        missing = AXIS_ORDER - axes.keys
        raise KeyError, "matrix axes are missing: #{missing.join(', ')}" unless missing.empty?

        extra = axes.keys - AXIS_ORDER
        raise ArgumentError, "matrix axes are unknown: #{extra.join(', ')}" unless extra.empty?

        AXIS_VALUES.each do |axis, expected|
          actual = axes.fetch(axis)
          next if actual == expected

          raise ArgumentError, "matrix axis #{axis} must be exactly #{expected.inspect}; got #{actual.inspect}"
        end
      end
    end
  end
end
