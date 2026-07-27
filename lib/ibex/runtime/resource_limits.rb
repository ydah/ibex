# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Immutable per-parser-session resource budgets.
    class ResourceLimits
      DEFAULT_MAX_STACK_DEPTH = 10_000 #: Integer
      DEFAULT_MAX_RECOVERY_ATTEMPTS = 100 #: Integer
      DEFAULT_MAX_INCREMENTAL_DECOMPOSED_NODES = 100_000 #: Integer
      DEFAULT_MAX_SESSION_MEMO_BYTES = 64 * 1024 * 1024 #: Integer

      attr_reader :max_stack_depth #: Integer
      attr_reader :max_recovery_attempts #: Integer
      attr_reader :max_incremental_decomposed_nodes #: Integer
      attr_reader :max_session_memo_bytes #: Integer

      # @rbs (?max_stack_depth: Integer, ?max_recovery_attempts: Integer,
      #   ?max_incremental_decomposed_nodes: Integer, ?max_session_memo_bytes: Integer) -> void
      def initialize(
        max_stack_depth: DEFAULT_MAX_STACK_DEPTH,
        max_recovery_attempts: DEFAULT_MAX_RECOVERY_ATTEMPTS,
        max_incremental_decomposed_nodes: DEFAULT_MAX_INCREMENTAL_DECOMPOSED_NODES,
        max_session_memo_bytes: DEFAULT_MAX_SESSION_MEMO_BYTES
      )
        validate_positive_integer(max_stack_depth, :max_stack_depth)
        validate_nonnegative_integer(max_recovery_attempts, :max_recovery_attempts)
        validate_nonnegative_integer(max_incremental_decomposed_nodes, :max_incremental_decomposed_nodes)
        validate_positive_integer(max_session_memo_bytes, :max_session_memo_bytes)
        @max_stack_depth = max_stack_depth
        @max_recovery_attempts = max_recovery_attempts
        @max_incremental_decomposed_nodes = max_incremental_decomposed_nodes
        @max_session_memo_bytes = max_session_memo_bytes
        freeze
      end

      # @rbs () -> Hash[Symbol, Integer]
      def to_h
        {
          max_stack_depth: @max_stack_depth,
          max_recovery_attempts: @max_recovery_attempts,
          max_incremental_decomposed_nodes: @max_incremental_decomposed_nodes,
          max_session_memo_bytes: @max_session_memo_bytes
        }.freeze
      end

      private

      # @rbs (Integer value, Symbol name) -> void
      def validate_positive_integer(value, name)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer"
      end

      # @rbs (Integer value, Symbol name) -> void
      def validate_nonnegative_integer(value, name)
        return if value.is_a?(Integer) && value >= 0

        raise ArgumentError, "#{name} must be a nonnegative Integer"
      end
    end
  end
end
