# frozen_string_literal: true

require_relative "../test_helper"

class ImpactSeedsTest < Minitest::Test
  def test_unknown_symbol_uses_impact_diagnostic
    grammar = normalize("class P\nrule\nstart: TOKEN\nend\n")

    error = assert_raises(Ibex::Error) { Ibex::Impact::Seeds.new(grammar, ["missing"]) }

    assert_equal "(impact):1:1: unknown symbol missing", error.message
  end

  def test_nullable_boundary_is_explicit
    grammar = normalize("class P\nrule\nstart: optional\noptional: | TOKEN\nend\n")
    seed = Ibex::Impact::Seeds.new(grammar, ["optional"])

    assert_equal true, seed.records.fetch(0).fetch(:nullable_boundary)
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
