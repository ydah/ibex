# frozen_string_literal: true

module Ibex
  module Quality
    # Derives tool-level comparison state from every registered claim.
    module ClaimStates
      module_function

      def comparison_state(tool_id, claims)
        registered = claims.select do |claim|
          claim.fetch("subjects").any? { |subject| subject.fetch("tool") == tool_id }
        end
        pending = registered.reject { |claim| claim.fetch("state") == "measured" }
        {
          "state" => state_for(registered, pending),
          "pending_claims" => pending.map { |claim| claim.fetch("id") },
          "reason" => reason_for(registered, pending)
        }
      end

      def verify!(tool, claims)
        expected = comparison_state(tool.fetch("id"), claims)
        %w[state pending_claims reason].each do |key|
          next if tool.fetch(key) == expected.fetch(key)

          raise "#{tool.fetch('id')}: #{key} must be derived from all registered comparative claims; " \
                "expected #{expected.fetch(key).inspect}"
        end
      end

      def state_for(registered, pending)
        return "not_compared" if registered.empty?
        return "compared" if pending.empty?

        "evidence_pending"
      end
      private_class_method :state_for

      def reason_for(registered, pending)
        return "No registered comparative claims." if registered.empty?

        if pending.empty?
          ids = registered.map { |claim| claim.fetch("id") }.join(", ")
          return "All registered comparative claims are measured: #{ids}."
        end

        details = pending.map { |claim| pending_detail(claim) }
        "Pending comparative claims: #{details.join('; ')}."
      end
      private_class_method :reason_for

      def pending_detail(claim)
        detail = if claim.fetch("state") == "review_pending"
                   "required subjective review incomplete"
                 else
                   missing = claim.fetch("missing_evidence").join(" | ").delete_suffix(".")
                   "missing evidence: #{missing}"
                 end
        "#{claim.fetch('id')} [#{detail}]"
      end
      private_class_method :pending_detail
    end
  end
end
