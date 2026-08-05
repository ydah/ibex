# frozen_string_literal: true

module Ibex
  module Quality
    # Reviewed independent authority for the declared matrix and interaction map.
    module RuntimeABIReviewedTestContract
      AXES = {
        "algorithm" => %w[slr lalr ielr lr1],
        "table" => %w[plain compact],
        "cst" => %w[off on],
        "locations" => %w[off on],
        "entries" => %w[single multi isolated]
      }.freeze

      INTERACTIONS = {
        "parser_semantics" => [%w[algorithm table cst locations entries], "matrix",
                               %w[test/tooling/matrix_runner_test.rb]],
        "generated_lexer" => [%w[algorithm table cst locations entries], "matrix_and_focused",
                              %w[test/codegen/lexer_test.rb test/frontend/lexer_test.rb]],
        "semantic_actions" => [%w[table locations cst], "matrix_and_focused",
                               %w[test/runtime/action_contract_test.rb test/analysis_no_exec_test.rb]],
        "table_encoding" => [%w[algorithm table cst entries], "matrix_and_focused",
                             %w[test/tables_test.rb test/runtime/table_format_test.rb]],
        "locations" => [%w[locations table cst entries], "matrix_and_focused",
                        %w[test/location_test.rb test/runtime/action_contract_test.rb]],
        "cst" => [%w[cst algorithm table locations entries], "matrix_and_focused",
                  %w[test/codegen/cst_runtime_integration_test.rb test/runtime/cst_serialize_test.rb]],
        "entry_modes" => [%w[entries algorithm table cst], "matrix_and_focused",
                          %w[test/codegen/multiple_start_test.rb]],
        "parser_drivers" => [%w[table cst locations], "focused_regression",
                             %w[test/runtime/parser_test.rb test/runtime/push_parser_test.rb
                                test/runtime/parser_table_session_test.rb]],
        "generated_ast" => [%w[algorithm table locations], "focused_regression",
                            %w[test/codegen/ast_test.rb test/tooling/matrix_runner_test.rb]],
        "recovery" => [%w[algorithm table cst entries], "focused_regression",
                       %w[test/runtime/repair_test.rb test/runtime/sync_recovery_test.rb]],
        "resource_limits" => [%w[algorithm table cst entries], "matrix_and_focused",
                              %w[test/runtime/resource_limits_test.rb]],
        "observation" => [%w[table cst locations], "focused_regression",
                          %w[test/runtime/observation_test.rb test/codegen/embedded_tracer_test.rb]],
        "incremental_cst" => [%w[cst table locations], "focused_regression",
                              %w[test/runtime/cst_incremental_test.rb]],
        "syntax_session" => [%w[cst table locations], "focused_regression",
                             %w[test/runtime/syntax_session_test.rb test/packaging/runtime_gem_test.rb]],
        "embedded_runtime" => [%w[table cst], "focused_regression",
                               %w[test/packaging/runtime_gem_test.rb test/codegen/ractor_shareability_test.rb]]
      }.freeze
    end
  end
end
