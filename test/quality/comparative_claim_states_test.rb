# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/comparative_claims"
require "tmpdir"
require "yaml"

class ComparativeClaimStatesTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REGISTRY = File.join(ROOT, "docs/registry/claims.yml")

  def test_tool_state_pending_claims_and_reason_are_derived_from_all_claims
    changed = document
    changed.fetch("comparison_set").first["state"] = "compared"
    assert_error(changed, "state must be derived from all registered comparative claims")

    changed = document
    changed.fetch("comparison_set").first.fetch("pending_claims").shift
    assert_error(changed, "pending_claims must be derived from all registered comparative claims")

    changed = document
    changed.fetch("comparison_set").first["reason"] = "Error-UX review is pending."
    assert_error(changed, "reason must be derived from all registered comparative claims")
  end

  def test_measured_r001_does_not_hide_pending_performance_claim
    claims = document.fetch("claims")
    claims.first["state"] = "measured"
    derived = Ibex::Quality::ClaimStates.comparison_state("racc", claims)

    assert_equal "evidence_pending", derived.fetch("state")
    assert_equal ["racc-public-performance-2026-07-31"], derived.fetch("pending_claims")
    assert_includes derived.fetch("reason"), "Complete formal public-performance result artifact"

    historical_performance = claims.find { |claim| claim.fetch("id") == "racc-public-performance-2026-07-31" }
    historical_performance["state"] = "measured"
    derived = Ibex::Quality::ClaimStates.comparison_state("racc", claims)
    assert_equal "compared", derived.fetch("state")
    assert_empty derived.fetch("pending_claims")
  end

  private

  def document
    YAML.safe_load(File.read(REGISTRY, encoding: Encoding::UTF_8), permitted_classes: [], aliases: false)
  end

  def assert_error(value, message)
    Dir.mktmpdir("comparative-claim-states-") do |directory|
      path = File.join(directory, "claims.yml")
      File.write(path, YAML.dump(value))
      error = assert_raises(RuntimeError) do
        Ibex::Quality::ComparativeClaims.new(root: ROOT, registry: path).verify!
      end
      assert_includes error.message, message
    end
  end
end
