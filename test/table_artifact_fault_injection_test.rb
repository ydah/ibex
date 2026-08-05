# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/table_artifact_fault_corpus"

class TableArtifactFaultInjectionTest < Minitest::Test
  include Ibex::TestSupport::TableArtifactFaultCorpus

  EXPECTED_CLASSES = %w[
    grammar-digest symbol-ids production-length production-lhs shift-target goto-target accept-cell
    default-reduction conflict-resolver compact-offset compact-check compact-value entry-state
    cst-metadata-digest table-hash report-hash manifest-hash truncated-artifact duplicate-artifact
  ].freeze

  def test_v1_inventory_is_closed_complete_and_single_fault
    inventory = fault_inventory
    faults = inventory.fetch("faults")
    ids = faults.map { |fault| fault.fetch("id") }
    classes = faults.map { |fault| fault.fetch("class") }

    assert_equal %w[ibex_table_fault_injection schema_version threat_model faults], inventory.keys
    assert_equal "v004", inventory.fetch("ibex_table_fault_injection")
    assert_equal 1, inventory.fetch("schema_version")
    assert_equal 1, inventory.dig("threat_model", "faults_per_run")
    assert_equal FAULT_METHODS.keys, ids
    assert_equal EXPECTED_CLASSES, classes
    assert_equal ERROR_PATTERNS.keys, FAULT_METHODS.keys
    assert_equal faults.length, faults.map { |fault| fault.fetch("id") }.uniq.length
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
end
