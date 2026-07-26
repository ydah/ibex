# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../benchmark/optimization_candidates"

class OptimizationCandidatesTest < Minitest::Test
  def test_case_candidate_preserves_runtime_result_and_automaton
    _source, input, automaton = OptimizationCandidates.build_inputs
    results = %w[table case].map do |variant|
      generated = OptimizationCandidates.generated_source(automaton, variant)
      namespace = Module.new
      namespace.module_eval(generated, "candidate-#{variant}.rb")
      [generated, namespace.const_get(:BenchmarkRepresentativeParser, false).new.parse(input)]
    end

    assert_equal results.first.fetch(1), results.last.fetch(1)
    assert_operator results.last.fetch(0).bytesize, :>, results.first.fetch(0).bytesize
    assert_includes results.last.fetch(0), "private :action_for_current_state"
  end

  def test_chain_audit_is_stable_for_the_representative_grammar
    assert_equal(
      {
        productions: 139,
        unit_productions: 45,
        actionless_unit_productions: 39,
        action_unit_productions: 6
      },
      OptimizationCandidates.chain_rule_audit
    )
  end

  def test_requires_five_isolated_runs
    error = assert_raises(OptionParser::InvalidArgument) do
      OptimizationCandidates.parse_options(["--runs", "4"])
    end

    assert_includes error.message, "at least five isolated runs"
  end
end
