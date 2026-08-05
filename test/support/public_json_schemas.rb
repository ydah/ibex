# frozen_string_literal: true

module Ibex
  module TestSupport
    module PublicJSONSchemas
      NAMES = %w[
        grammar-ir-v1.schema.json automaton-ir-v1.schema.json
        grammar-ir-v2.schema.json automaton-ir-v2.schema.json
        grammar-ir-v3.schema.json automaton-ir-v3.schema.json
        lexer-ir-v1.schema.json explain-v1.schema.json
        benchmark-v1.schema.json benchmark-v2.schema.json
        generation-manifest-v1.schema.json error-ux-v1.schema.json
        error-ux-review-v1.schema.json error-ux-round2-v1.schema.json
        runtime-event-v1.schema.json
        runtime-coverage-v1.schema.json table-simulation-v1.schema.json
        migration-check-v1.schema.json fuzz-v1.schema.json
        fuzz-regression-v1.schema.json reduce-v1.schema.json
        reduce-v2.schema.json verify-v1.schema.json equiv-v1.schema.json
        metrics-v1.schema.json construction-profile-v1.schema.json
        lexer-profile-v1.schema.json
        table-artifact-v1.schema.json verification-report-v1.schema.json
        diff-v1.schema.json fix-v1.schema.json fix-v2.schema.json
        fix-v3.schema.json bison-import-v1.schema.json
      ].freeze
    end
  end
end
