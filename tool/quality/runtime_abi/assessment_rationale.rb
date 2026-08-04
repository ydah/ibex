# frozen_string_literal: true

require_relative "reviewed_policy"

module Ibex
  module Quality
    # Enforces minimal rationale shape and the repository-owned template sentinel.
    module RuntimeABIAssessmentRationale
      ERROR = "runtime ABI assessment rationale must replace the template sentinel and include a Unicode letter"

      def self.verify!(value)
        raise ERROR unless value.is_a?(String)

        normalized = value.gsub(/\p{Space}+/u, " ").strip
        raise ERROR if normalized.empty?
        raise ERROR if normalized == RuntimeABIReviewedPolicy::RATIONALE_SENTINEL
        raise ERROR unless normalized.match?(/\p{L}/u)
      end
    end
  end
end
