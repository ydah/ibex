# frozen_string_literal: true

require_relative "../test_helper"

class ImpactSeverityTest < Minitest::Test
  def test_kind_levels_are_ordered
    assert_equal "medium", Ibex::Impact::Severity.level_for_kind("reference")
    assert_equal "high", Ibex::Impact::Severity.level_for_kind("first")
    assert_equal "low", Ibex::Impact::Severity.level_for_kind("other")
    assert_equal "high", Ibex::Impact::Severity.max("medium", "high")
  end

  def test_fail_on_is_opt_in
    report = { automaton: { conflicts: { added: [{ id: "new" }] }, unreachable: [] }, symbols: [], actions: [] }

    refute Ibex::Impact::Severity.fails?(report, [])
    assert Ibex::Impact::Severity.fails?(report, ["new_conflict"])
  end

  def test_unknown_gate_is_rejected
    error = assert_raises(OptionParser::InvalidArgument) do
      Ibex::Impact::Severity.validate_gates(["not_a_gate"])
    end

    assert_includes error.message, "unknown --fail-on value"
  end
end
