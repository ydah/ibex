# frozen_string_literal: true

require_relative "../test_helper"

class SyntaxSessionTest < Minitest::Test # rubocop:disable Metrics/ClassLength
  SOURCE = <<~GRAMMAR
    class SyntaxServiceParser
    pragma cst
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/ { (@execution_sentinels ||= []) << :lexer; lexeme.to_i }
      PLUS '+'
    end
    rule
    start: expression { raise "parser action executed" }
    expression: NUM PLUS NUM { raise "parser action executed" }
    end
  GRAMMAR

  LIST_SOURCE = <<~GRAMMAR
    class SyntaxServiceListParser
    pragma cst
    token NUM PLUS
    lexer
      NUM /[0-9]+/
      PLUS '+'
    end
    rule
    start: list { raise "parser action executed" }
    list: list PLUS NUM { raise "parser action executed" }
        | NUM { raise "parser action executed" }
    end
  GRAMMAR

  MULTI_ENTRY_SOURCE = <<~GRAMMAR
    class SyntaxServiceEntriesParser
    pragma extended
    pragma cst
    start expression atom
    token NUM PLUS
    lexer
      skip /[[:space:]]+/
      NUM /[0-9]+/
      PLUS '+'
    end
    rule
    expression: NUM PLUS NUM { raise "parser action executed" }
    atom: NUM { raise "parser action executed" }
    end
  GRAMMAR

  LOCATED_SOURCE = SOURCE.sub(
    'start: expression { raise "parser action executed" }',
    'start: expression { result = @1; raise "parser action executed" }'
  )

  PROFILE = :trusted_application_code

  def test_profile_is_truthful_and_must_be_acknowledged
    parser_class = generate

    assert_equal PROFILE, parser_class.syntax_execution_profile
    error = assert_raises(Ibex::Runtime::SyntaxSessionTrustError) do
      parser_class.syntax_session("1 + 2")
    end
    assert_match(/lexer actions/, error.message)

    session = parser_class.syntax_session("1 + 2", execution_profile: PROFILE)
    assert_equal PROFILE, session.execution_profile
  end

  def test_declarative_profile_cannot_be_enabled_by_overriding_a_flag
    parser_class = generate
    parser_class.define_singleton_method(:syntax_execution_profile) { :declarative }

    error = assert_raises(Ibex::Runtime::SyntaxSessionTrustError) do
      parser_class.syntax_session("1 + 2", execution_profile: :declarative)
    end

    assert_match(/not available/, error.message)
  end

  def test_open_and_edits_execute_lexer_actions_but_never_parser_actions
    session = generate.syntax_session("1 + 2", execution_profile: PROFILE)
    runtime_parser = session.instance_variable_get(:@incremental).instance_variable_get(:@parser)

    assert_equal %i[lexer lexer], runtime_parser.instance_variable_get(:@execution_sentinels)
    refute_respond_to session.result, :value
    assert_equal "1 + 2", session.result.syntax_root.to_source

    result = session.apply_edits(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "3")]
    )

    assert_equal %i[lexer lexer lexer lexer], runtime_parser.instance_variable_get(:@execution_sentinels)
    assert_equal "1 + 3", result.syntax_root.to_source
    refute_respond_to result, :value
  end

  def test_plain_compact_and_location_modes_share_the_session_contract
    [
      [:plain, SOURCE],
      [:compact, SOURCE],
      [:plain, LOCATED_SOURCE],
      [:compact, LOCATED_SOURCE]
    ].each do |table, source|
      parser_class = generate(source, table: table)
      assert parser_class::PARSER_TABLES.fetch(:uses_locations), "CST parsing must retain source locations"

      session = parser_class.syntax_session("1 + 2", execution_profile: PROFILE)
      result = session.apply_edits(
        [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "7")]
      )

      assert_equal "1 + 7", result.syntax_root.to_source
      assert_predicate result, :success?
    end
  end

  def test_all_algorithms_tables_and_multi_entry_strategies_share_the_session_contract
    cases = %i[slr lalr ielr lr1].product(%i[plain compact], [false, true])
    assert_equal 16, cases.length

    cases.each do |algorithm, table, entry_isolation|
      parser_class = generate(
        MULTI_ENTRY_SOURCE,
        mode: :extended,
        algorithm: algorithm,
        table: table,
        entry_isolation: entry_isolation
      )
      assert_equal %i[expression atom], parser_class::ENTRY_STATES.keys

      session = parser_class.syntax_session("1 + 2", execution_profile: PROFILE)
      result = session.apply_edits(
        [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "9")]
      )
      fresh = parser_class.syntax_session(session.source_text, execution_profile: PROFILE).result

      assert_syntax_session_equivalent(fresh, result)
      assert_predicate result, :success?
    end
  end

  def test_parser_failure_reports_diagnostics_and_existing_expected_tokens
    result = generate.syntax_session("1 2", execution_profile: PROFILE).result

    assert_equal :syntax_error, result.status
    refute_predicate result, :success?
    refute_empty result.diagnostics
    assert_equal :syntax_error, result.diagnostics.first.kind
    assert_includes result.expected_tokens, "PLUS"
    assert_predicate result.syntax_root, :contains_error?
  end

  def test_reuse_and_fallback_metrics_are_operation_local
    limits = Ibex::Runtime::ResourceLimits.new(max_incremental_decomposed_nodes: 0)
    session = generate.syntax_session("1 + 2", execution_profile: PROFILE, resource_limits: limits)

    initial = session.result
    result = session.apply_edits(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "8")]
    )

    assert_equal 0, initial.revision
    assert_equal 1, result.revision
    assert_predicate result.metrics, :fallback?
    assert_includes result.metrics.fallback_reasons, :decomposition_budget
    assert_equal initial.syntax_root.tokens.length, initial.metrics.token_count
    assert_equal 0, initial.metrics.reused_tokens
    assert_equal result.syntax_root.tokens.length, result.metrics.token_count
    assert_operator result.metrics.reused_ratio, :>=, 0.0
  end

  def test_full_lexical_fallback_reports_final_token_count_without_reuse
    session = generate.syntax_session("1 + 2", execution_profile: PROFILE)

    result = session.apply_edits(
      [Ibex::Runtime::CST::TextEdit.new(start: 2, delete_length: 1, insert_text: "@")]
    )

    assert_equal :syntax_error, result.status
    assert_includes result.metrics.fallback_reasons, :lexical_error
    assert_equal result.syntax_root.tokens.length, result.metrics.token_count
    assert_operator result.metrics.token_count, :>, 0
    assert_equal 0, result.metrics.reused_tokens
    assert_equal 0.0, result.metrics.reused_ratio
  end

  def test_error_sequence_with_shrinking_memos_matches_fresh_session
    parser_class = generate(LIST_SOURCE)
    session = parser_class.syntax_session("1+2+3", execution_profile: PROFILE)
    edits = [
      [1, 2, "", "1+3"],
      [1, 2, "@", "1@"],
      [1, 0, "+", "1+@"],
      [2, 0, "12", "1+12@"],
      [0, 2, "+", "+12@"],
      [3, 1, " ", "+12 "]
    ]

    edits.each do |start, delete_length, insert_text, expected_source|
      incremental = session.apply_edits(
        [Ibex::Runtime::CST::TextEdit.new(
          start: start, delete_length: delete_length, insert_text: insert_text
        )]
      )
      fresh = parser_class.syntax_session(session.source_text, execution_profile: PROFILE).result

      assert_equal expected_source.b, session.source_text.text
      assert_syntax_session_equivalent(fresh, incremental)
    end
  end

  def test_cancellation_is_not_reported_as_a_success_and_preserves_source
    token = Ibex::Runtime::CancellationToken.new
    session = generate.syntax_session("1 + 2", execution_profile: PROFILE, cancellation: token)
    previous_result = session.result
    token.cancel!

    assert_raises(Ibex::Runtime::SyntaxSessionCancelled) do
      session.apply_edits(
        [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "9")]
      )
    end

    assert_equal "1 + 2", session.source_text.text
    assert_same previous_result, session.result
  end

  def test_cancelled_open_stops_before_lexer_actions
    token = Ibex::Runtime::CancellationToken.new
    token.cancel!

    assert_raises(Ibex::Runtime::SyntaxSessionCancelled) do
      generate.syntax_session("1 + 2", execution_profile: PROFILE, cancellation: token)
    end
  end

  def test_cancellation_during_parse_rolls_back_the_incremental_session
    parser_class = generate
    token = Ibex::Runtime::CancellationToken.new
    cancel_during_shift = false
    parser_class.define_method(:on_shift) do |_token_id, _value, _state|
      token.cancel! if cancel_during_shift
    end
    session = parser_class.syntax_session(
      "1 + 2",
      execution_profile: PROFILE,
      cancellation: token
    )
    previous_result = session.result
    cancel_during_shift = true

    assert_raises(Ibex::Runtime::SyntaxSessionCancelled) do
      session.apply_edits(
        [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "7")]
      )
    end

    assert_equal "1 + 2", session.source_text.text
    assert_same previous_result, session.result
  end

  def test_failed_operation_evidence_does_not_leak_into_the_next_result
    parser_class = generate
    parser_limits = Ibex::Runtime::ResourceLimits.new(max_recovery_attempts: 0)
    session = parser_class.syntax_session(
      "1 + 2", execution_profile: PROFILE, resource_limits: parser_limits
    )
    previous_result = session.result
    invalid = Ibex::Runtime::CST::TextEdit.new(start: 2, delete_length: 1, insert_text: "")

    assert_raises(Ibex::Runtime::SyntaxSessionResourceLimitError) do
      session.apply_edits([invalid])
    end
    assert_equal "1 + 2", session.source_text.text
    assert_same previous_result, session.result

    valid = Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "9")
    completed = session.apply_edits([valid])
    fresh = parser_class.syntax_session(
      session.source_text, execution_profile: PROFILE, resource_limits: parser_limits
    ).result
    assert_syntax_session_equivalent(fresh, completed)
    assert_empty completed.expected_tokens
    refute_predicate completed.metrics, :fallback?
  end

  def test_cancellation_after_the_last_runtime_checkpoint_applies_to_the_next_operation
    parser_class = generate
    token = Ibex::Runtime::CancellationToken.new
    cancel_after_reuse = false
    parser_class.define_method(:emit_incremental_event) do |type, data|
      super(type, data)
      token.cancel! if cancel_after_reuse && type == :cst_reuse
    end
    session = parser_class.syntax_session(
      "1 + 2",
      execution_profile: PROFILE,
      cancellation: token
    )
    cancel_after_reuse = true

    completed = session.apply_edits(
      [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "6")]
    )

    assert_equal "1 + 6", completed.syntax_root.to_source
    assert_equal "1 + 6", session.source_text.text
    assert_raises(Ibex::Runtime::SyntaxSessionCancelled) do
      session.apply_edits(
        [Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "7")]
      )
    end
  end

  def test_service_limits_reject_source_edit_count_and_inserted_bytes
    parser_class = generate
    source_limit = Ibex::Runtime::SyntaxSessionLimits.new(max_source_bytes: 4)
    error = assert_raises(Ibex::Runtime::SyntaxSessionResourceLimitError) do
      parser_class.syntax_session("12345", execution_profile: PROFILE, limits: source_limit)
    end
    assert_equal :source_bytes, error.resource

    limits = Ibex::Runtime::SyntaxSessionLimits.new(
      max_source_bytes: 16,
      max_edits_per_operation: 1,
      max_inserted_bytes: 1
    )
    session = parser_class.syntax_session("1+2", execution_profile: PROFILE, limits: limits)
    too_many = [
      Ibex::Runtime::CST::TextEdit.new(start: 0, delete_length: 0, insert_text: ""),
      Ibex::Runtime::CST::TextEdit.new(start: 3, delete_length: 0, insert_text: "")
    ]
    error = assert_raises(Ibex::Runtime::SyntaxSessionResourceLimitError) { session.apply_edits(too_many) }
    assert_equal :edits_per_operation, error.resource

    edit = Ibex::Runtime::CST::TextEdit.new(start: 0, delete_length: 0, insert_text: "12")
    error = assert_raises(Ibex::Runtime::SyntaxSessionResourceLimitError) { session.apply_edits([edit]) }
    assert_equal :inserted_bytes, error.resource
  end

  def test_source_and_edit_shape_ranges_and_encoding_are_validated
    parser_class = generate
    utf16 = "1 + 2".encode(Encoding::UTF_16LE)
    assert_raises(Encoding::CompatibilityError) do
      parser_class.syntax_session(utf16, execution_profile: PROFILE)
    end

    session = parser_class.syntax_session("1+2", execution_profile: PROFILE)
    assert_raises(ArgumentError) { session.apply_edits([Object.new]) }
    outside = Ibex::Runtime::CST::TextEdit.new(start: 3, delete_length: 1, insert_text: "")
    assert_raises(RangeError) { session.apply_edits([outside]) }
    assert_equal "1+2", session.source_text.text
  end

  def test_result_values_are_immutable
    result = generate.syntax_session("1 2", execution_profile: PROFILE).result

    assert_predicate result, :frozen?
    assert_predicate result.diagnostics, :frozen?
    assert_predicate result.expected_tokens, :frozen?
    assert_predicate result.metrics, :frozen?
    assert_predicate result.metrics.fallback_reasons, :frozen?
    assert result.expected_tokens.all?(&:frozen?)
    assert result.diagnostics.all?(&:frozen?)
    assert(result.diagnostics.all? { |diagnostic| deeply_frozen?(diagnostic.data) })
  end

  def test_concurrent_edits_are_serialized_at_the_service_boundary
    session = generate(LIST_SOURCE).syntax_session("1+2+3", execution_profile: PROFILE)
    failures = Queue.new
    edits = [
      Ibex::Runtime::CST::TextEdit.new(start: 0, delete_length: 1, insert_text: "4"),
      Ibex::Runtime::CST::TextEdit.new(start: 4, delete_length: 1, insert_text: "5")
    ]
    threads = edits.map do |edit|
      Thread.new do
        session.apply_edits([edit])
      rescue StandardError => e
        failures << e
      end
    end
    threads.each(&:join)

    no_failures = failures.empty?
    failure_message = no_failures ? nil : failures.pop.message
    assert no_failures, failure_message
    assert_equal "4+2+5", session.source_text.text
    assert_equal 2, session.result.revision
  end

  def test_random_edits_match_fresh_syntax_sessions # rubocop:disable Metrics/AbcSize
    parser_class = generate(LIST_SOURCE)
    session = parser_class.syntax_session("1+2+3", execution_profile: PROFILE)
    random = Random.new(20_260_805)

    200.times do
      source = session.source_text.text
      positions = source.enum_for(:scan, /[0-9]/).map { Regexp.last_match.begin(0) }
      position = positions.fetch(random.rand(positions.length))
      edit = Ibex::Runtime::CST::TextEdit.new(
        start: position,
        delete_length: 1,
        insert_text: random.rand(10).to_s
      )
      incremental = session.apply_edits([edit])
      fresh = parser_class.syntax_session(
        session.source_text,
        execution_profile: PROFILE
      ).result

      assert_equal fresh.syntax_root.green, incremental.syntax_root.green
      assert_equal fresh.syntax_root.to_source, incremental.syntax_root.to_source
      assert_equal diagnostic_snapshot(fresh.diagnostics), diagnostic_snapshot(incremental.diagnostics)
    end
  end

  def test_random_insert_delete_replace_and_error_edits_match_fresh_sessions
    parser_class = generate(LIST_SOURCE)
    session = parser_class.syntax_session("1+2+3", execution_profile: PROFILE)
    random = Random.new(20_260_806)
    inserts = ["", "0", "12", "+", "++", " ", "@", "?"]

    500.times do
      source = session.source_text.text
      start = random.rand(source.bytesize + 1)
      delete_length = random.rand([source.bytesize - start, 3].min + 1)
      insert_text = inserts.fetch(random.rand(inserts.length))
      edit = Ibex::Runtime::CST::TextEdit.new(
        start: start, delete_length: delete_length, insert_text: insert_text
      )
      expected_source = session.source_text.apply([edit]).text
      incremental = session.apply_edits([edit])
      fresh = parser_class.syntax_session(session.source_text, execution_profile: PROFILE).result

      assert_equal expected_source, session.source_text.text
      assert_syntax_session_equivalent(fresh, incremental)
    end
  end

  private

  def diagnostic_snapshot(diagnostics)
    diagnostics.map do |diagnostic|
      [diagnostic.kind, diagnostic.to_h]
    end
  end

  def assert_syntax_session_equivalent(fresh, incremental)
    assert_equal fresh.syntax_root.source_text.text, incremental.syntax_root.source_text.text
    assert_equal fresh.syntax_root.to_source, incremental.syntax_root.to_source
    assert_equal fresh.syntax_root.green, incremental.syntax_root.green
    assert_equal fresh.syntax_root.green.flags, incremental.syntax_root.green.flags
    assert_equal diagnostic_snapshot(fresh.diagnostics), diagnostic_snapshot(incremental.diagnostics)
    assert_equal fresh.expected_tokens, incremental.expected_tokens
  end

  def deeply_frozen?(value)
    return false unless value.frozen?
    return value.all? { |key, child| deeply_frozen?(key) && deeply_frozen?(child) } if value.is_a?(Hash)
    return value.all? { |child| deeply_frozen?(child) } if value.is_a?(Array)

    true
  end

  def generate(source = SOURCE, mode: :default, algorithm: :lalr, table: :compact, entry_isolation: false)
    ast = Ibex::Frontend::Parser.new(source, file: "syntax-session.y", mode: mode).parse
    grammar = Ibex::Normalizer.new(ast, mode: mode).normalize
    automaton = Ibex::LALR::Builder.new(
      grammar, algorithm: algorithm, entry_isolation: entry_isolation
    ).build
    generated = Ibex::Codegen::Ruby.new(automaton, table: table).generate
    namespace = Module.new
    namespace.module_eval(generated, "generated_syntax_session.rb")
    namespace.const_get(grammar.class_name)
  end
end
