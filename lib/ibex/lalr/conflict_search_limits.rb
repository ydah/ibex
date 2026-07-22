# frozen_string_literal: true

module Ibex
  module LALR
    # Validates search limits and measures sentences against the token budget.
    module ConflictSearchLimits
      DEFAULT_MAX_TOKENS = 32
      DEFAULT_MAX_CONFIGURATIONS = 50_000

      def self.validate!(max_tokens:, max_configurations:)
        validate_limit!(:max_tokens, max_tokens)
        validate_limit!(:max_configurations, max_configurations)
      end

      def self.validate_limit!(name, value)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer"
      end

      private

      def within_token_budget?(prefix, suffix)
        prefix.length + suffix.length + conflict_lookahead_length <= @max_tokens
      end

      def room_for_token?(prefix, suffix)
        prefix.length + suffix.length + conflict_lookahead_length < @max_tokens
      end

      def conflict_lookahead_length = @lookahead.zero? ? 0 : 1
    end
  end
end
