# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"

class RuntimeABIAssessmentTest < Minitest::Test
  include RuntimeABITestProject

  RUNTIME_PATH = "lib/ibex/runtime/cst/kind.rb"
  FULL_VERIFICATION =
    "verification: [bundle exec rake quality:runtime_abi, " \
    "bundle exec ruby -Itest test/runtime/cst_serialize_test.rb]"

  def test_duplicate_or_dangling_markers_are_rejected
    [
      [Ibex::Quality::RuntimeABIAssessment::START,
       "#{Ibex::Quality::RuntimeABIAssessment::START}\n#{Ibex::Quality::RuntimeABIAssessment::START}"],
      [Ibex::Quality::RuntimeABIAssessment::FINISH,
       "#{Ibex::Quality::RuntimeABIAssessment::FINISH}\n#{Ibex::Quality::RuntimeABIAssessment::FINISH}"]
    ].each do |before, after|
      with_runtime_abi_root do |root|
        event = fixture_event_copy(root)
        rewrite_event_body(event, before, after)

        error = assert_raises(RuntimeError) { verify(root, event) }
        assert_includes error.message, "exactly one complete structured ABI assessment"
      end
    end
  end

  def test_compatible_parser_table_sidecar_with_readme_evidence_is_rejected
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      rewrite_event_body(event, "surfaces: [runtime_api, cst]", "surfaces: [parser_table]")
      rewrite_event_body(event, "abi_choice: current_contract", "abi_choice: sidecar")
      rewrite_event_body(
        event,
        "evidence: [#{RUNTIME_PATH}, test/runtime/cst_serialize_test.rb]",
        "evidence: [README.md]"
      )

      error = assert_raises(RuntimeError) { verify(root, event) }
      assert_includes error.message, "evidence must be a changed path or owned regression test"
    end
  end

  def test_sidecar_rejects_parser_table_even_with_valid_evidence
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      rewrite_event_body(event, "surfaces: [runtime_api, cst]", "surfaces: [parser_table]")
      rewrite_event_body(event, "abi_choice: current_contract", "abi_choice: sidecar")

      error = assert_raises(RuntimeError) { verify(root, event) }
      assert_includes error.message, "sidecar requires compatible generation_metadata"
    end
  end

  def test_placeholder_rationale_is_rejected
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      original = "rationale: The runtime implementation preserves the current table and CST contracts."
      rewrite_event_body(event, original, "rationale: TODO")

      error = assert_raises(RuntimeError) { verify(root, event) }
      assert_includes error.message, "rationale must be substantive"
    end
  end

  def test_unknown_interaction_and_unowned_test_are_rejected
    [
      ["affected_interactions: [cst]", "affected_interactions: [unknown]", "documented interaction ids"],
      ["tests: [test/runtime/cst_serialize_test.rb]", "tests: [test/runtime/parser_test.rb]",
       "tests are not owned"]
    ].each do |before, after, message|
      with_runtime_abi_root do |root|
        event = fixture_event_copy(root)
        rewrite_event_body(event, before, after)

        error = assert_raises(RuntimeError) { verify(root, event) }
        assert_includes error.message, message
      end
    end
  end

  def test_verification_rejects_arbitrary_commands_and_missing_coverage
    cases = [
      [
        FULL_VERIFICATION,
        "verification: [bundle exec rake quality:runtime_abi, echo trusted]",
        "non-allowlisted command"
      ],
      [
        FULL_VERIFICATION,
        "verification: [bundle exec ruby -Itest test/runtime/cst_serialize_test.rb]",
        "must run bundle exec rake quality:runtime_abi"
      ],
      [
        FULL_VERIFICATION,
        "verification: [bundle exec rake quality:runtime_abi]",
        "must run every selected test"
      ]
    ]
    cases.each do |before, after, message|
      with_runtime_abi_root do |root|
        event = fixture_event_copy(root)
        rewrite_event_body(event, before, after)

        error = assert_raises(RuntimeError) { verify(root, event) }
        assert_includes error.message, message
      end
    end
  end

  def test_evidence_must_include_every_runtime_facing_change
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      evidence = "evidence: [#{RUNTIME_PATH}, test/runtime/cst_serialize_test.rb]"
      rewrite_event_body(event, evidence, "evidence: [test/runtime/cst_serialize_test.rb]")

      error = assert_raises(RuntimeError) { verify(root, event) }
      assert_includes error.message, "evidence omits changed runtime-facing paths"
    end
  end

  def test_choice_compatibility_table_rejects_contradictions
    cases = [
      [["state: compatible", "state: breaking"], "current_contract requires compatible"],
      [["abi_choice: current_contract", "abi_choice: new_table_format"],
       "new_table_format requires breaking parser_table and regeneration"],
      [["abi_choice: current_contract", "abi_choice: new_ir_version"],
       "new_ir_version requires breaking state"],
      [["abi_choice: current_contract", "abi_choice: new_runtime_major"],
       "new_runtime_major requires breaking runtime surface"]
    ]
    cases.each do |replacement, message|
      with_runtime_abi_root do |root|
        event = fixture_event_copy(root)
        rewrite_event_body(event, *replacement)

        error = assert_raises(RuntimeError) { verify(root, event) }
        assert_includes error.message, message
      end
    end
  end

  def test_choice_compatibility_table_accepts_each_concrete_choice
    cases = [
      [["surfaces: [runtime_api, cst]", "surfaces: [generation_metadata]"],
       ["abi_choice: current_contract", "abi_choice: sidecar"]],
      [["state: compatible", "state: breaking"],
       ["surfaces: [runtime_api, cst]", "surfaces: [parser_table]"],
       ["abi_choice: current_contract", "abi_choice: new_table_format"],
       ["regeneration: not_required", "regeneration: required"]],
      [["state: compatible", "state: breaking"],
       ["surfaces: [runtime_api, cst]", "surfaces: [grammar_ir]"],
       ["abi_choice: current_contract", "abi_choice: new_ir_version"]],
      [["state: compatible", "state: breaking"],
       ["surfaces: [runtime_api, cst]", "surfaces: [runtime_api]"],
       ["abi_choice: current_contract", "abi_choice: new_runtime_major"]]
    ]
    cases.each do |replacements|
      with_runtime_abi_root do |root|
        event = fixture_event_copy(root)
        replacements.each { |replacement| rewrite_event_body(event, *replacement) }
        verify(root, event)
      end
    end
  end

  private

  def verify(root, event)
    verify_runtime_event(root, event: event, changed_paths: [RUNTIME_PATH])
  end
end
