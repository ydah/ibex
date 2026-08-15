# frozen_string_literal: true

require_relative "../test_helper"

class ImpactActionImpactTest < Minitest::Test
  def test_rhs_changes_are_reported_without_inspecting_action_source
    before = normalize("class P\ntoken A B\nrule\nstart: A { raise 'before action' }\nend\n")
    after = normalize("class P\ntoken A B\nrule\nstart: A B { raise 'after action' }\nend\n")

    findings = Ibex::Impact::ActionImpact.new(before, after, affected_names: ["start"]).to_a

    assert_equal 1, findings.length
    assert_equal "medium", findings.fetch(0).fetch(:severity)
    assert_equal "rhs_length_changed", findings.fetch(0).fetch(:reason)
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact-action.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
