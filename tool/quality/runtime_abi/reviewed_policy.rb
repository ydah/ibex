# frozen_string_literal: true

module Ibex
  module Quality
    # Reviewed head authority; pull requests also retain trusted-base paths.
    module RuntimeABIReviewedPolicy
      REQUIRED_RUNTIME_PATHS = %w[
        .github/pull_request_template.md .github/workflows/main.yml Rakefile
        docs/runtime-abi-evolution.md docs/test-interactions.md
        tool/quality/runtime_abi.rb tool/quality/runtime_abi/**/*
        test/quality/runtime_abi*_test.rb test/support/runtime_abi_test_project.rb
        test/fixtures/runtime_abi/**/*
        ibex.gemspec ibex-runtime.gemspec lib/ibex/version.rb
        lib/ibex/runtime.rb lib/ibex/runtime/**/* lib/ibex/runtime/version.rb
        lib/ibex/tables.rb lib/ibex/tables/**/* sig/ibex/tables.rbs
        sig/ibex/runtime.rbs sig/ibex/runtime/**/* sig/ibex/tables/**/*
        lib/ibex/codegen.rb lib/ibex/codegen/**/* sig/ibex/codegen.rbs sig/ibex/codegen/**/*
        lib/ibex/frontend/generated_parser.rb
        lib/ibex/ir.rb lib/ibex/ir/**/* sig/ibex/ir.rbs sig/ibex/ir/**/*
        schema/grammar-ir-v*.schema.json schema/automaton-ir-v*.schema.json
        schema/lexer-ir-v*.schema.json schema/cst-v*.json
        test/matrix.yml test/support/matrix_contract.rb test/support/matrix_runner.rb
        test/tooling/matrix_runner_test.rb
        tool/quality/golden.rb test/golden/**/*
      ].freeze

      ASSESSMENT = {
        "states" => %w[compatible breaking not_applicable],
        "surfaces" => %w[
          parser_table grammar_ir automaton_ir lexer_ir runtime_api embedded_runtime generation_metadata
          cst test_matrix policy none
        ],
        "abi_choices" => %w[current_contract new_table_format new_ir_version new_runtime_major sidecar none],
        "regeneration" => %w[required not_required not_applicable],
        "required_fields" => %w[
          state surfaces abi_choice regeneration rationale affected_interactions evidence tests verification
        ]
      }.freeze
    end
  end
end
