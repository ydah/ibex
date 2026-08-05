# frozen_string_literal: true

module Ibex
  module ErrorUXRound2
    # Static H003 problem, semantic, trust, review, and stop-policy declarations.
    module Policy
      REQUIRED_DIMENSIONS = %w[
        delimiter-heavy statement-language stateful-string-lexer eof-error
        multi-error-continuation unknown-token lexer-failure
      ].freeze

      module_function

      def problem
        {
          "statement" => "Repository evidence must test diagnostic and repair behavior beyond the ten R001 JSON cases.",
          "required_dimensions" => REQUIRED_DIMENSIONS,
          "excluded_dimensions" => [
            {
              "dimension" => "indentation-sensitive-language",
              "status" => "excluded-unimplemented",
              "reason" => "ibex-has-no-indentation-tokenization-contract"
            }
          ]
        }
      end

      def semantics
        {
          "expected_tokens" => "Parser diagnostics report the exact runtime expected-token set; " \
                               "lexer failures have no parser state.",
          "proposed_edit" => "A repository-authored source edit is evaluated separately from " \
                             "the bounded runtime repair plan.",
          "fresh_reparse" => "Edits are applied by byte range and parsed by a newly allocated generated parser.",
          "semantic_value_risk" => "Syntactic acceptance does not establish that inserted, deleted, or replaced " \
                                   "semantic values match user intent."
        }
      end

      def trust_boundary
        {
          "fixture_code" => "repository-owned-trusted",
          "generated_code_execution" => "enabled-for-listed-fixtures-only",
          "external_code_execution" => "forbidden",
          "statement" => "The capture executes generated lexer and action code only from the four " \
                         "allowlisted repository fixtures."
        }
      end

      def external_subjective_gate
        {
          "status" => "HOLD",
          "reason" => "no-external-review-records",
          "allowed_labels" => %w[useful misleading unsafe unclear],
          "records" => []
        }
      end

      def limitations
        [
          { "code" => "repository-only", "statement" => "No external workload or reviewer is represented." },
          {
            "code" => "single-selected-repair",
            "statement" => "Bounded repair reports one selected plan, not every equal-cost edit."
          },
          {
            "code" => "acceptance-not-intent",
            "statement" => "A successful fresh parse does not prove intended program semantics."
          },
          {
            "code" => "no-indentation",
            "statement" => "Indentation diagnostics are excluded because no indentation contract exists."
          }
        ]
      end

      def kill_conditions
        [
          {
            "code" => "fixture-drift",
            "statement" => "Fail when a fixture or corpus digest changes without regenerated evidence."
          },
          { "code" => "coverage-loss", "statement" => "Fail when a required H003 dimension has no case." },
          { "code" => "r001-mutation", "statement" => "Fail when the normative R001 snapshot digest changes." },
          {
            "code" => "review-overclaim",
            "statement" => "Fail when HOLD has a review record or a pending case has labels."
          },
          {
            "code" => "fresh-reparse-regression",
            "statement" => "Fail when a proposed edit no longer produces its committed fresh outcome."
          }
        ]
      end
    end
  end
end
