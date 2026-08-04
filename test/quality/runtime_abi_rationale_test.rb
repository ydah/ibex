# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/quality/runtime_abi"
require_relative "../support/runtime_abi_test_project"

class RuntimeABIRationaleTest < Minitest::Test
  include RuntimeABITestProject

  RUNTIME_PATH = "lib/ibex/runtime/cst/kind.rb"

  def test_placeholder_phrases_are_rejected_by_containment
    %w[TODO TBD FIXME template placeholder].each do |phrase|
      assert_rationale_rejected("Runtime behavior remains compatible, but #{phrase} wording is still present here.")
    end
  end

  def test_placeholder_detection_normalizes_unicode_and_ignores_separators
    ["Ｔ－Ｏ－Ｄ－Ｏ", "T B D", "F-I-X-M-E", "t e m p l a t e", "p_l_a_c_e_h_o_l_d_e_r",
     "T\u2003O\u2003D\u2003O"].each do |phrase|
      assert_rationale_rejected("Runtime behavior remains compatible, but #{phrase} wording is still present here.")
    end
  end

  def test_placeholder_detection_ignores_symbols_emoji_and_combining_marks
    ["T+O+D+O", "T💣O💣D💣O", "T\u0338O\u0338D\u0338O"].each do |phrase|
      assert_rationale_rejected("Runtime behavior remains compatible, but #{phrase} wording is still present here.")
    end
  end

  def test_rationale_rejects_exact_obvious_filler_examples
    examples = [
      "Compatibility remains unresolved; FIXME after the release tests complete.",
      "............................................................",
      "safe safe safe safe safe safe safe safe safe safe"
    ]
    examples.each { |rationale| assert_rationale_rejected(rationale) }
  end

  def test_rationale_rejects_low_diversity_and_zero_width_controls
    examples = [
      "aaaa bbbb aaaa bbbb aaaa bbbb aaaa bbbb",
      "The runtime contract remains\u200B compatible because behavior is unchanged for every parser session.",
      "The runtime contract remains compatible because behavior is\u2060 unchanged for every parser session.",
      "\uFEFFThe runtime contract remains compatible because behavior is unchanged for every parser session."
    ]
    examples.each { |rationale| assert_rationale_rejected(rationale) }
  end

  def test_rationale_rejects_exact_repetition_boundary_and_periodic_filler
    fillers = [
      "safe safe safe safe safe alpha beta gamma delta epsilon",
      "runtimecontract runtimecontract runtimecontract runtimecontract"
    ]
    fillers.each { |rationale| assert_rationale_rejected(rationale) }
  end

  def test_rationale_accepts_japanese_without_whitespace_tokens
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      replace_rationale(event, "実行時契約は既存の表形式を維持し、入力前の検証動作と解析結果も変更しません。")

      verify_runtime_event(root, event: event, changed_paths: [RUNTIME_PATH])
    end
  end

  def test_rationale_accepts_arabic_unicode_prose
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      rationale = "يحافظ عقد وقت التشغيل على تنسيق الجدول الحالي " \
                  "ولا يغير التحقق قبل الإدخال أو نتائج التحليل."
      replace_rationale(event, rationale)

      verify_runtime_event(root, event: event, changed_paths: [RUNTIME_PATH])
    end
  end

  def test_rationale_does_not_join_natural_prose_into_placeholder_terms
    rationales = [
      "The runtime contract sends current tables to downstream consumers while preserving every parser result.",
      "The parser records prefix metadata while preserving the current runtime contract and table layout."
    ]

    rationales.each do |rationale|
      with_runtime_abi_root do |root|
        event = fixture_event_copy(root)
        replace_rationale(event, rationale)

        verify_runtime_event(root, event: event, changed_paths: [RUNTIME_PATH])
      end
    end
  end

  private

  def assert_rationale_rejected(rationale)
    with_runtime_abi_root do |root|
      event = fixture_event_copy(root)
      replace_rationale(event, rationale)

      error = assert_raises(RuntimeError) do
        verify_runtime_event(root, event: event, changed_paths: [RUNTIME_PATH])
      end
      assert_includes error.message, "rationale must be substantive"
    end
  end

  def replace_rationale(event, rationale)
    original = "rationale: The runtime implementation preserves the current table and CST contracts."
    rewrite_event_body(event, original, "rationale: #{rationale}")
  end
end
