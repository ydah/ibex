# frozen_string_literal: true

require_relative "../test_helper"

class RepairSemanticsDocumentationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DOCUMENT = File.join(ROOT, "docs/repair-semantics.md")

  EXPECTED_COVERAGE = {
    "policy-and-default-off" => "test/runtime/repair_test.rb",
    "dijkstra-priority-and-outcomes" => "test/runtime/repair_characterization_test.rb",
    "typed-search-outcomes" => "test/runtime/repair_characterization_test.rb",
    "values-locations-and-replay" => "test/runtime/repair_test.rb",
    "hooks-actions-and-observers" => "test/runtime/repair_test.rb",
    "pull-and-push-bounds" => "test/runtime/repair_test.rb",
    "cst-representation" => "test/codegen/cst_test.rb",
    "cst-source-fidelity" => "test/runtime/cst_fidelity_property_test.rb",
    "syntax-only-repair-projection" => "test/runtime/syntax_repair_test.rb"
  }.freeze

  def test_characterization_maps_every_required_concept_to_executable_evidence
    assert_equal EXPECTED_COVERAGE, coverage_rows
    EXPECTED_COVERAGE.each_value do |path|
      assert File.file?(File.join(ROOT, path)), path
    end
  end

  def test_public_characterization_names_the_current_result_and_value_boundaries
    source = File.binread(DOCUMENT)

    assert_includes source, "typed outcome (`:selected`, `:need_input`, `:exhausted`, or\n`:not_found`)"
    assert_includes source, "internal `NEED_INPUT`"
    assert_includes source, "| insert | `nil`"
    assert_includes source, "replacement's retained value"
    assert_includes source, "speculative\nsearch never runs them"
    assert_includes source, "not a source-byte\noffset"
  end

  def test_documented_defaults_match_the_runtime_policy
    policy = Ibex::Runtime::RepairPolicy.new

    assert_equal [1, 1, 2, 3, 5_000, 8, 3, 256], [
      policy.insert_cost, policy.delete_cost, policy.replace_cost, policy.max_cost,
      policy.max_configurations, policy.max_lookahead, policy.success_shifts, policy.max_stack
    ]
  end

  private

  def coverage_rows
    source = File.binread(DOCUMENT)
    block = source[/<!-- repair-semantics:coverage:start -->(.*?)<!-- repair-semantics:coverage:end -->/m, 1]
    refute_nil block

    block.lines.filter_map do |line|
      next unless line.start_with?("|")

      cells = line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
      next if %w[Concept ---].include?(cells.fetch(0))

      [cells.fetch(0), cells.fetch(1).delete("`")]
    end.to_h
  end
end
