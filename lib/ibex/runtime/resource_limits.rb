# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Immutable per-parser-session resource budgets.
    class ResourceLimits
      DEFAULT_MAX_STACK_DEPTH = 10_000 #: Integer
      DEFAULT_MAX_RECOVERY_ATTEMPTS = 100 #: Integer

      attr_reader :max_stack_depth #: Integer
      attr_reader :max_recovery_attempts #: Integer

      # @rbs (?max_stack_depth: Integer, ?max_recovery_attempts: Integer) -> void
      def initialize(
        max_stack_depth: DEFAULT_MAX_STACK_DEPTH,
        max_recovery_attempts: DEFAULT_MAX_RECOVERY_ATTEMPTS
      )
        validate_positive_integer(max_stack_depth, :max_stack_depth)
        validate_nonnegative_integer(max_recovery_attempts, :max_recovery_attempts)
        @max_stack_depth = max_stack_depth
        @max_recovery_attempts = max_recovery_attempts
        freeze
      end

      # @rbs () -> Hash[Symbol, Integer]
      def to_h
        {
          max_stack_depth: @max_stack_depth,
          max_recovery_attempts: @max_recovery_attempts
        }.freeze
      end

      private

      # @rbs (untyped value, Symbol name) -> void
      def validate_positive_integer(value, name)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer"
      end

      # @rbs (untyped value, Symbol name) -> void
      def validate_nonnegative_integer(value, name)
        return if value.is_a?(Integer) && value >= 0

        raise ArgumentError, "#{name} must be a nonnegative Integer"
      end
    end
  end
end
