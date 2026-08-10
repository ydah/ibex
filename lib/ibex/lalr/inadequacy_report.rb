# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

require "json"
require_relative "../verify/action_correspondence"

module Ibex
  module LALR
    # Diagnostic-only report for canonical-vs-LALR action differences.  It is
    # intentionally separate from normal construction because it enumerates a
    # canonical LR(1) reference.
    class InadequacyReport
      # @rbs (IR::Automaton canonical, IR::Automaton target, ?max_pairs: Integer) -> void
      def initialize(canonical, target, max_pairs: nil)
        @canonical = canonical
        @target = target
        @max_pairs = max_pairs
      end

      # @rbs () -> Hash[Symbol, report_value]
      def to_h
        result = Verify::ActionCorrespondence.new(@canonical, @target, max_pairs: @max_pairs).verify
        {
          algorithm: @target.algorithm,
          canonical_algorithm: @canonical.algorithm,
          explored_pairs: result.explored,
          truncated: result.truncated,
          differences: result.differences.map do |difference|
            {
              kind: difference.kind, canonical_state: difference.canonical_state,
              target_state: difference.target_state, symbol: difference.symbol,
              canonical: difference.canonical, target: difference.target
            }
          end
        }
      end

      # @rbs () -> String
      def to_json(*)
        "#{JSON.pretty_generate(to_h)}\n"
      end
    end
  end
end
# steep:ignore:end
