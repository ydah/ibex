# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../verify/verifier_test"

class VerifierTrustBoundaryDocumentationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DOCUMENT = File.join(ROOT, "docs/verifier-trust-boundary.md")

  def test_document_is_linked_from_public_reference_pages
    assert_includes File.binread(File.join(ROOT, "README.md")), "docs/verifier-trust-boundary.md"
    assert_includes File.binread(File.join(ROOT, "docs/architecture.md")), "verifier-trust-boundary.md"
    assert_includes File.binread(File.join(ROOT, "docs/grammar-reference.md")), "verifier-trust-boundary.md"
  end

  def test_named_check_modes_match_the_verifier
    documented = rows("verifier-checks").to_h { |row| [row.fetch(0), row.fetch(1)] }
    expected = Ibex::Verify::Verifier::DEFAULT_CHECKS.to_h { |id| [id, "default"] }
    Ibex::Verify::Verifier::STRICT_CHECKS.each { |id| expected[id] = "strict" }

    assert_equal expected, documented
  end

  def test_supported_algorithms_match_both_automaton_schemas
    schemas = %w[v1 v2].map do |version|
      path = File.join(ROOT, "schema/automaton-ir-#{version}.schema.json")
      JSON.parse(File.binread(path)).fetch("properties").fetch("algorithm").fetch("enum")
    end
    assert_equal schemas.fetch(0), schemas.fetch(1)

    documented = rows("verifier-algorithms").map { |row| row.fetch(0).delete("`") }
    assert_equal schemas.fetch(0), documented
  end

  def test_documented_limits_match_default_verifier_result
    result = Ibex::Verify::Verifier.new(harness.send(:build_calculator)).verify
    documented = rows("verifier-limits").to_h do |row|
      [row.fetch(0).delete("`"), Integer(row.fetch(1).delete("`"))]
    end

    assert_equal({ "--max-states" => result.bounds.fetch(:max_states),
                   "--max-items" => result.bounds.fetch(:max_items) }, documented)
  end

  def test_fault_mapping_matches_the_committed_mutation_corpus
    documented = rows("verifier-faults").to_h do |row|
      [row.fetch(0).delete("`"), row.fetch(1).split(", ")]
    end

    assert_equal observed_faults, documented
  end

  def test_explicit_non_goals_remain_complete
    documented = rows("verifier-non-goals").map { |row| row.fetch(0).delete("`") }
    expected = %w[
      source-to-ir generated-ruby runtime semantic-actions lexer-actions resolver-policy grammar-properties
      ielr-adequacy data-only-artifact security
    ]

    assert_equal expected, documented
  end

  private

  def rows(marker)
    source = File.binread(DOCUMENT)
    block = source[/<!-- #{marker}:start -->(.*?)<!-- #{marker}:end -->/m, 1]
    refute_nil block, "missing #{marker} documentation block"

    block.lines.filter_map do |line|
      next unless line.start_with?("|")

      cells = line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
      cells unless cells.fetch(0).match?(/\A-+\z/) ||
                   %w[ID Limit Boundary Fault].include?(cells.fetch(0)) || cells.fetch(0) == "Automaton IR value"
    end
  end

  def observed_faults
    VerifyVerifierTest::FAULTS.to_h do |fault|
      document = harness.send(fault == :epsilon_cycle ? :epsilon_document : :calculator_document)
      harness.send(:inject_fault, document, fault)
      automaton = Ibex::IR::Validator.validate(JSON.generate(document))
      ids = Ibex::Verify::Verifier.new(automaton, strict: true).verify.violations.map(&:id).uniq
      [fault.to_s, ids]
    end
  end

  def harness
    @harness ||= VerifyVerifierTest.new("documentation contract")
  end
end
