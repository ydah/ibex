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

  def test_inserting_an_alternative_does_not_realign_existing_actions
    before = normalize(<<~GRAMMAR)
      class P
      token A B C
      rule
      start: A B { result = val[0] } | C { result = val[0] }
      end
    GRAMMAR
    after = normalize(<<~GRAMMAR)
      class P
      token A B C
      rule
      start: A { result = val[0] } | A B { result = val[0] } | C { result = val[0] }
      end
    GRAMMAR

    assert_empty Ibex::Impact::ActionImpact.new(before, after, affected_names: ["start"]).to_a
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact-action.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
