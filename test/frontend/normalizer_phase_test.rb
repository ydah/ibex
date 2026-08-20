# frozen_string_literal: true

require_relative "../test_helper"

class NormalizerPhaseTest < Minitest::Test
  def test_normalization_exposes_completed_phase_boundary
    source = "class PhaseParser\nrule\nstart: TOKEN\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "phase.y").parse
    normalizer = Ibex::Normalizer.new(ast)

    normalizer.normalize

    assert_equal :complete, normalizer.phase_guard.phase
    assert_same normalizer.phase_guard, normalizer.context
  end

  def test_phase_guard_rejects_out_of_order_phases
    assert_same Ibex::Normalize::PhaseGuard, Ibex::Normalize::Context

    phase_guard = Ibex::Normalize::PhaseGuard.new

    error = assert_raises(RuntimeError) { phase_guard.begin_phase!(:symbols) }

    assert_match(/expected declarations, got symbols/, error.message)
    assert_equal :initialized, phase_guard.phase
  end
end
