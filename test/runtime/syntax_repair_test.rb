# frozen_string_literal: true

require_relative "../test_helper"

class SyntaxRepairTest < Minitest::Test
  PROFILE = :trusted_application_code
  SOURCE = <<~GRAMMAR
    class SyntaxRepairParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/
      PLUS '+'
    end
    rule
    start: expression { raise "parser production action executed" }
    expression: NUM PLUS NUM { raise "parser production action executed" }
    end
    ---- inner
    def on_repair(_plan)
      raise("application repair callback executed")
    end
  GRAMMAR

  PUNCTUATION_SOURCE = <<~GRAMMAR
    class SyntaxRepairPunctuationParser
    pragma cst
    token NUM
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/
      on /[+]/ { |text| emit text, text }
    end
    rule
    start: expression { raise "parser production action executed" }
    expression: NUM '+' NUM { raise "parser production action executed" }
    end
  GRAMMAR

  # rubocop:disable Metrics/AbcSize
  def test_insertion_returns_byte_edit_missing_cst_and_fresh_acceptance_without_value
    session = syntax_session("1 2")
    original_result = session.result

    result = session.repair(token_text: { "PLUS" => "+" })

    assert_equal :accepted, result.status
    assert_equal :selected, result.bounded_status
    assert_predicate result, :accepted?
    assert_predicate result, :progress?
    refute_respond_to result, :value
    refute_respond_to result.validation, :value
    assert_equal "1 2", result.syntax_root.to_source
    assert result.syntax_root.tokens.any?(&:missing?)
    assert_equal "1 +2", result.updated_source.text
    assert_equal "1 +2", result.validation.syntax_root.to_source
    assert_predicate result.validation, :success?
    assert_equal [{ start: 2, delete_length: 0, insert_text: "+".b }], text_edit_hashes(result)
    assert_equal :insert, result.plan.edits.fetch(0).kind
    assert_equal "", result.plan.edits.fetch(0).original_text
    assert_equal "+", result.plan.edits.fetch(0).replacement_text
    assert_same original_result, session.result
    assert_equal "1 2", session.source_text.text
  end
  # rubocop:enable Metrics/AbcSize

  def test_deletion_uses_original_token_range_without_a_spelling_map
    result = syntax_session("1 + + 2").repair

    assert_equal :accepted, result.status
    assert_equal [{ start: 4, delete_length: 1, insert_text: "".b }], text_edit_hashes(result)
    edit = result.plan.edits.fetch(0)
    assert_equal :delete, edit.kind
    assert_equal "+", edit.original_text
    assert_equal "", edit.replacement_text
    assert_equal "1 +  2", result.updated_source.text
    assert_equal "1 +  2", result.validation.syntax_root.to_source
  end

  def test_replacement_has_token_metadata_but_never_preserves_a_semantic_value
    policy = Ibex::Runtime::RepairPolicy.new(
      insert_cost: 5, delete_cost: 5, replace_cost: 1, max_cost: 1, success_shifts: 1
    )
    result = syntax_session("1 + +").repair(policy: policy, token_text: { "NUM" => "0" })

    assert_equal :accepted, result.status
    assert_equal [{ start: 4, delete_length: 1, insert_text: "0".b }], text_edit_hashes(result)
    edit = result.plan.edits.fetch(0)
    assert_equal :replace, edit.kind
    assert_equal "+", edit.original_text
    assert_equal "0", edit.replacement_text
    refute edit.to_h.key?(:value)
    refute result.plan.runtime_plan.to_h.to_s.include?("parser production action executed")
  end

  def test_missing_named_token_spelling_fails_closed_with_metadata
    result = syntax_session("1 2").repair

    assert_equal :unavailable, result.status
    assert_equal :selected, result.bounded_status
    assert_equal :missing_token_text, result.reason
    assert_equal :insert, result.plan.edits.fetch(0).kind
    assert_nil result.plan.edits.fetch(0).replacement_text
    assert_empty result.text_edits
    assert_nil result.updated_source
    assert_nil result.validation
  end

  def test_punctuation_literal_needs_no_explicit_spelling
    parser_class = generate(PUNCTUATION_SOURCE)
    session = parser_class.syntax_session("1 2", execution_profile: PROFILE)

    result = session.repair

    assert_equal :accepted, result.status
    assert_equal "+", result.plan.edits.fetch(0).replacement_text
  end

  def test_exhaustion_and_no_plan_are_distinct_fail_closed_results
    exhausted = syntax_session("1 2").repair(
      policy: Ibex::Runtime::RepairPolicy.new(max_configurations: 1), token_text: { "PLUS" => "+" }
    )
    no_plan = syntax_session("1 2").repair(
      policy: Ibex::Runtime::RepairPolicy.new(
        insert_cost: 2, delete_cost: 2, replace_cost: 2, max_cost: 1
      ),
      token_text: { "PLUS" => "+" }
    )

    assert_equal %i[exhausted exhausted search_exhausted],
                 [exhausted.status, exhausted.bounded_status, exhausted.reason]
    assert_equal %i[not_found not_found no_repair_plan], [no_plan.status, no_plan.bounded_status, no_plan.reason]
    [exhausted, no_plan].each do |result|
      assert_nil result.plan
      assert_empty result.text_edits
      assert_nil result.validation
      assert_equal "1 2", result.syntax_root.to_source
    end
  end

  # rubocop:disable Metrics/AbcSize
  def test_fresh_validation_distinguishes_progress_from_rejection
    progress = syntax_session("1 2").repair(token_text: { "PLUS" => "+ +" })
    rejected = syntax_session("1 2").repair(token_text: { "PLUS" => "@" })

    assert_equal :progress, progress.status
    assert_predicate progress, :progress?
    refute_predicate progress, :accepted?
    assert_equal "1 + +2", progress.updated_source.text
    assert progress.updated_source.text.start_with?(progress.validation.syntax_root.to_source)
    assert_equal :syntax_error, progress.validation.status

    assert_equal :rejected, rejected.status
    refute_predicate rejected, :progress?
    assert_equal "1 @2", rejected.updated_source.text
    assert rejected.updated_source.text.start_with?(rejected.validation.syntax_root.to_source)
    assert_equal :syntax_error, rejected.validation.status
  end
  # rubocop:enable Metrics/AbcSize

  def test_multiple_selected_segments_are_not_flattened_across_token_coordinates
    policy = Ibex::Runtime::RepairPolicy.new(max_cost: 1, success_shifts: 1)

    result = syntax_session("1 2 3").repair(policy: policy, token_text: { "PLUS" => "+" })

    assert_equal :unavailable, result.status
    assert_equal :multiple_repair_segments, result.reason
    assert_nil result.plan
    assert_empty result.text_edits
    assert_nil result.validation
  end

  def test_cancellation_and_service_limits_are_not_results
    cancellation = Ibex::Runtime::CancellationToken.new
    session = generate.syntax_session("1 2", execution_profile: PROFILE, cancellation: cancellation)
    cancellation.cancel!
    assert_raises(Ibex::Runtime::SyntaxSessionCancelled) do
      session.repair(token_text: { "PLUS" => "+" })
    end

    limits = Ibex::Runtime::SyntaxSessionLimits.new(max_inserted_bytes: 0)
    session = generate.syntax_session("1 2", execution_profile: PROFILE, limits: limits)
    error = assert_raises(Ibex::Runtime::SyntaxSessionResourceLimitError) do
      session.repair(token_text: { "PLUS" => "+" })
    end
    assert_equal :inserted_bytes, error.resource
  end

  def test_result_graph_is_immutable
    result = syntax_session("1 2").repair(token_text: { "PLUS" => "+" })

    assert_predicate result, :frozen?
    assert_predicate result.text_edits, :frozen?
    assert_predicate result.diagnostics, :frozen?
    assert_predicate result.plan, :frozen?
    assert_predicate result.plan.edits, :frozen?
    assert(result.plan.edits.all?(&:frozen?))
  end

  private

  def syntax_session(source)
    generate.syntax_session(source, execution_profile: PROFILE)
  end

  def generate(source = SOURCE)
    ast = Ibex::Frontend::Parser.new(source, file: "syntax_repair.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    generated = Ibex::Codegen::Ruby.new(automaton).generate
    namespace = Module.new
    namespace.module_eval(generated, "generated_syntax_repair.rb")
    namespace.const_get(grammar.class_name)
  end

  def text_edit_hashes(result)
    result.text_edits.map do |edit|
      { start: edit.start, delete_length: edit.delete_length, insert_text: edit.insert_text }
    end
  end
end
