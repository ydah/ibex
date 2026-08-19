# frozen_string_literal: true

require_relative "../test_helper"

class NormalizerPhaseTest < Minitest::Test
  def test_normalization_exposes_completed_phase_boundary
    source = "class PhaseParser\nrule\nstart: TOKEN\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "phase.y").parse
    normalizer = Ibex::Normalizer.new(ast)

    normalizer.normalize

    assert_equal :complete, normalizer.context.phase
  end

  def test_context_rejects_out_of_order_phases
    context = Ibex::Normalize::Context.new

    error = assert_raises(RuntimeError) { context.begin_phase!(:symbols) }

    assert_match(/expected declarations, got symbols/, error.message)
    assert_equal :initialized, context.phase
  end
end
