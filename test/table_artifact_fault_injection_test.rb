# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/table_artifact_fault_corpus"

class TableArtifactFaultInjectionTest < Minitest::Test
  include Ibex::TestSupport::TableArtifactFaultCorpus

  EXPECTED_CLASSES = %w[
    grammar-digest symbol-ids production-length production-lhs shift-target goto-target accept-cell
    default-reduction conflict-resolver compact-offset compact-check compact-value entry-state
    cst-metadata-digest table-hash report-hash report-manifest-hash manifest-hash truncated-artifact duplicate-artifact
  ].freeze

  EXPECTED_THREAT_MODEL = {
    "faults_per_run" => 1,
    "payload_digest_may_be_refreshed" => true,
    "derived_cost_may_be_refreshed_only_for_structural_survivor" => true,
    "outer_binding_may_be_refreshed_only_to_reach_the_named_invariant" => true,
    "coherent_all_layer_replacement" => "excluded-authenticity-and-semantic-derivation"
  }.freeze

  EXPECTED_FAULT_CONTRACTS = {
    "V004-GRAMMAR-DIGEST" => ["grammar-digest", "bundle", "ir.grammar.digest mismatch"],
    "V004-SYMBOL-ID" => ["symbol-ids", "table-structure", "symbols id must be contiguous and ordered"],
    "V004-PRODUCTION-LENGTH" => ["production-length", "table-structure", "production rhs_length must match rhs"],
    "V004-PRODUCTION-LHS" => ["production-lhs", "table-structure", "production lhs must reference a nonterminal"],
    "V004-SHIFT-TARGET" => ["shift-target", "table-structure", "shift action references a missing state"],
    "V004-GOTO-TARGET" => ["goto-target", "table-structure", "goto value references a missing state"],
    "V004-ACCEPT-CELL" => ["accept-cell", "table-structure", "accept is only valid for eof"],
    "V004-DEFAULT-REDUCTION" => ["default-reduction", "table-structure",
                                 "default action must be an error or reduction"],
    "V004-CONFLICT-RESOLVER" => ["conflict-resolver", "report-table-binding",
                                 "table.artifact_digest mismatch"],
    "V004-COMPACT-OFFSET" => ["compact-offset", "table-structure",
                              "canonical minimal row-displacement layout"],
    "V004-COMPACT-CHECK" => ["compact-check", "table-structure", "compact check references a missing state"],
    "V004-COMPACT-VALUE" => ["compact-value", "table-structure",
                             "compact value and check occupancy must match"],
    "V004-ENTRY-STATE" => ["entry-state", "table-structure", "entry references a missing state"],
    "V004-CST-METADATA-DIGEST" => ["cst-metadata-digest", "table-identity",
                                   "cst_metadata_digest does not match payload cst"],
    "V004-TABLE-HASH" => ["table-hash", "table-identity", "payload_digest does not match the canonical payload"],
    "V004-REPORT-HASH" => ["report-hash", "report-identity", "evidence_digest mismatch"],
    "V004-REPORT-MANIFEST-HASH" => ["report-manifest-hash", "manifest-binding",
                                    "verification report manifest digest mismatch"],
    "V004-MANIFEST-HASH" => ["manifest-hash", "manifest-binding", "parser table manifest digest mismatch"],
    "V004-TRUNCATED-ARTIFACT" => ["truncated-artifact", "table-loader", "invalid JSON"],
    "V004-DUPLICATE-ARTIFACT" => ["duplicate-artifact", "manifest-binding",
                                  "exactly one parser_table artifact"]
  }.freeze

  def test_v1_inventory_is_closed_complete_and_single_fault
    inventory = fault_inventory
    faults = inventory.fetch("faults")
    ids = faults.map { |fault| fault.fetch("id") }
    classes = faults.map { |fault| fault.fetch("class") }
    contracts = faults.to_h do |fault|
      [fault.fetch("id"), fault.values_at("class", "layer", "invariant")]
    end

    assert_equal %w[ibex_table_fault_injection schema_version threat_model faults], inventory.keys
    assert_equal "v004", inventory.fetch("ibex_table_fault_injection")
    assert_equal 1, inventory.fetch("schema_version")
    assert_equal EXPECTED_THREAT_MODEL, inventory.fetch("threat_model")
    assert_equal FAULT_METHODS.keys, ids
    assert_equal EXPECTED_CLASSES, classes
    assert_equal EXPECTED_FAULT_CONTRACTS, contracts
    assert_equal ERROR_PATTERNS.keys, FAULT_METHODS.keys
    assert_equal faults.length, faults.map { |fault| fault.fetch("id") }.uniq.length
    faults.each { |fault| assert_equal %w[id class layer invariant], fault.keys, fault.fetch("id") }
  end

  def test_every_v1_fault_is_rejected_at_its_named_invariant
    fault_inventory.fetch("faults").each do |fault|
      id = fault.fetch("id")
      result = exercise_table_artifact_fault(id)

      refute_nil result.error, "#{id} escaped validation"
      assert_match ERROR_PATTERNS.fetch(id), result.error.message, id
      assert_equal STRUCTURAL_SURVIVORS.include?(id), result.standalone_accepted, id
    end
  end

  def test_outer_binding_faults_are_structurally_valid_before_bundle_rejection
    STRUCTURAL_SURVIVORS.each do |id|
      result = exercise_table_artifact_fault(id)

      assert result.standalone_accepted, id
      assert_instance_of Ibex::VerificationReport::ValidationError, result.error, id
    end
  end

  def test_mutations_are_independent_and_do_not_change_the_canonical_fixture
    before = File.binread(TABLE_FIXTURE_PATH)
    FAULT_METHODS.each_key { |id| exercise_table_artifact_fault(id) }

    assert_equal before, File.binread(TABLE_FIXTURE_PATH)
    assert Ibex::TableArtifact.load(before)
  end

  def test_fault_outcomes_are_path_independent_and_actions_do_not_execute
    assert_includes V004_SOURCE, 'raise "V004 semantic action executed"'
    outcomes = []
    ["plain-root", "unicode-δ-root"].each do |name|
      Dir.mktmpdir(name) do |directory|
        outcomes << with_bundle_directory(directory) do
          FAULT_METHODS.each_key.map do |id|
            result = exercise_table_artifact_fault(id)
            [id, result.error.class.name, result.error.message, result.standalone_accepted]
          end
        end
      end
    end

    assert_equal outcomes.fetch(0), outcomes.fetch(1)
  end
end
