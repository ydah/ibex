# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Verify
    # One stable verifier finding.
    class Violation
      attr_reader :id #: String
      attr_reader :location #: String
      attr_reader :message #: String

      # @rbs (id: String, location: String, message: String) -> void
      def initialize(id:, location:, message:)
        @id = id.freeze
        @location = location.freeze
        @message = message.freeze
        freeze
      end

      # @rbs () -> Hash[Symbol, String]
      def to_h
        { id: @id, location: @location, message: @message }.freeze
      end
    end

    # Immutable independent-verification report.
    class Result
      # @rbs! type report_value = String | Integer | bool | Array[String] | Hash[Symbol, Integer] | Array[Hash[Symbol, String]]

      attr_reader :algorithm #: String
      attr_reader :strict #: bool
      attr_reader :checks #: Array[String]
      attr_reader :violations #: Array[Violation]
      attr_reader :bounds #: Hash[Symbol, Integer]

      # @rbs (algorithm: String, strict: bool, checks: Array[String], violations: Array[Violation],
      #   bounds: Hash[Symbol, Integer]) -> void
      def initialize(algorithm:, strict:, checks:, violations:, bounds:)
        @algorithm = algorithm.freeze
        @strict = strict
        @checks = checks.dup.freeze
        @violations = violations.dup.freeze
        @bounds = bounds.dup.freeze
        freeze
      end

      # @rbs () -> bool
      def valid? = @violations.empty?

      # @rbs () -> Hash[Symbol, report_value]
      def to_h
        {
          ibex_report: "verify", schema_version: 1, algorithm: @algorithm,
          strict: @strict, checks: @checks, bounds: @bounds,
          result: valid? ? "valid" : "invalid",
          violations: @violations.map(&:to_h)
        }.freeze
      end
    end

    class BudgetExceeded < Ibex::Error
      attr_reader :bounds #: Hash[Symbol, Integer]

      # @rbs (String message, bounds: Hash[Symbol, Integer]) -> void
      def initialize(message, bounds:)
        @bounds = bounds.dup.freeze
        super(message)
      end
    end
  end
end
