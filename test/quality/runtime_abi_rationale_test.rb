# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"

class RuntimeABIRationaleTest < Minitest::Test
  include RuntimeABITestProject

  RUNTIME_PATH = "lib/ibex/runtime/cst/kind.rb"
  SENTINEL = Ibex::Quality::RuntimeABIReviewedPolicy::RATIONALE_SENTINEL

  def test_rationale_rejects_unchanged_sentinel_and_whitespace_normalized_form
    rationales = [
      SENTINEL,
      " \nReplace  this\tplaceholder with the compatibility\u2003reasoning.\n "
    ]
    rationales.each { |rationale| assert_rationale_rejected(rationale) }
  end

  def test_rationale_rejects_wrong_type_empty_and_letterless_values
    [nil, 7, [], "", " \t\n\u2003", "1234 --"].each { |rationale| assert_rationale_rejected(rationale) }
  end

  def test_rationale_accepts_an_explicit_sentinel_replacement
    assert_rationales_accepted(
      ["Compatibility reasoning supplied by the author.", "replace this placeholder with the compatibility reasoning."]
    )
  end

  def test_rationale_accepts_ordinary_identifiers
    identifiers = %w[
      prefix_metadata prefixMetadata suffix_metadata suffix-metadata suffixMetadata
      autoDocumentation auto_documentation photo-documentation fix-metadata
    ]
    assert_rationales_accepted(identifiers)
  end

  def test_rationale_accepts_todo_like_content_for_human_review
    rationales = ["TODO", "TBD", "FIXME later", "T+O+D+O", "修正TODO予定"]
    assert_rationales_accepted(rationales)
  end

  def test_rationale_accepts_multilingual_prose
    rationales = [
      "実行時契約は既存の表形式を維持し、入力前の検証動作と解析結果も変更しません。",
      "يحافظ عقد وقت التشغيل على تنسيق الجدول الحالي ولا يغير التحقق قبل الإدخال أو نتائج التحليل."
    ]
    assert_rationales_accepted(rationales)
  end

  private

  def assert_rationales_accepted(rationales)
    with_runtime_abi_root do |root|
      rationales.each do |rationale|
        event = fixture_event_copy(root)
        replace_rationale(event, rationale)

        verify_runtime_event(root, event: event, changed_paths: [RUNTIME_PATH])
      end
    end
  end

  def assert_rationale_rejected(rationale)
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      replace_rationale(event, rationale)

      error = assert_raises(RuntimeError) do
        verify_runtime_event(root, event: event, changed_paths: [RUNTIME_PATH])
      end
      assert_includes error.message, "rationale must replace the template sentinel"
    end
  end

  def replace_rationale(event, rationale)
    original = "rationale: The runtime implementation preserves the current table and CST contracts."
    rewrite_event_body(event, original, "rationale: #{JSON.generate(rationale)}")
  end
end
