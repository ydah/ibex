# frozen_string_literal: true

require_relative "../test_helper"

class FrontendDiagnosticsTest < Minitest::Test
  MULTIPLE_ERRORS = <<~GRAMMAR
    class P
    expect nope
    token GOOD
    rule
    broken: A | ) | B
    later: GOOD
    end
  GRAMMAR
  private_constant :MULTIPLE_ERRORS

  def test_success_returns_the_normal_ast_and_parsed_document
    source = "class P\nrule\nstart: TOKEN\nend\n"
    parser = Ibex::Frontend::Parser.new(source, file: "valid.y")
    result = parser.parse_with_diagnostics

    assert_predicate result, :success?
    refute_predicate result, :partial?
    assert_empty result.diagnostics
    assert_equal parser.parse.to_h, result.ast.to_h
    assert_same result.ast, result.document.ast
    assert_equal source, result.document.render
  end

  def test_collects_ordered_errors_and_returns_an_explicit_partial_ast
    result = Ibex::Frontend::Parser.new(MULTIPLE_ERRORS, file: "multiple.y").parse_with_diagnostics
    lines = result.diagnostics.map { |diagnostic| diagnostic.location.line }

    refute_predicate result, :success?
    assert_predicate result, :partial?
    assert_equal [2, 5], lines
    assert_equal %w[frontend.syntax_error frontend.syntax_error], result.diagnostics.map(&:code)
    assert_equal %w[broken later], result.ast.rules.map(&:lhs)
    assert_nil result.document.ast
    assert_equal MULTIPLE_ERRORS, result.document.render

    first = result.diagnostics.first
    assert_equal ["integer"], first.expected
    assert_equal "nope", first.received
    assert_predicate first, :frozen?
    assert_predicate first.expected, :frozen?
  end

  def test_lexical_and_syntax_errors_share_the_same_result
    source = "class P\n@\nexpect nope\nrule\nstart: TOKEN\nend\n"
    parser = Ibex::Frontend::Parser.new(source, file: "mixed.y")
    error = assert_raises(Ibex::Error) { parser.parse }
    result = parser.parse_with_diagnostics
    lines = result.diagnostics.map { |diagnostic| diagnostic.location.line }

    assert_equal 'mixed.y:2:1: unexpected character "@"', error.message
    assert_equal %i[lexical syntax], result.diagnostics.map(&:phase)
    assert_equal [2, 3], lines
    assert_equal ["start"], result.ast.rules.map(&:lhs)
    assert_equal source, result.document.render
  end

  def test_limit_is_positive_and_stops_before_unreported_recovery
    parser = Ibex::Frontend::Parser.new(MULTIPLE_ERRORS, file: "limited.y")

    assert_raises(ArgumentError) { parser.parse_with_diagnostics(max_diagnostics: 0) }
    assert_raises(ArgumentError) { parser.parse_with_diagnostics(max_diagnostics: -1) }
    assert_raises(ArgumentError) { parser.parse_with_diagnostics(max_diagnostics: 1.5) }

    result = parser.parse_with_diagnostics(max_diagnostics: 1)
    assert_equal 1, result.diagnostics.length
    assert_nil result.ast
    refute_predicate result, :success?
  end

  def test_limit_selects_the_earliest_diagnostic_across_phases
    source = "class P\nexpect nope\n@\nrule\nstart: TOKEN\nend\n"
    parser = Ibex::Frontend::Parser.new(source, file: "earliest.y")
    result = parser.parse_with_diagnostics(max_diagnostics: 1)

    assert_equal 1, result.diagnostics.length
    assert_equal :syntax, result.diagnostics.first.phase
    assert_equal 2, result.diagnostics.first.location.line
  end

  def test_lexical_collection_is_bounded_and_consecutive_invalid_source_is_coalesced
    lexer = Ibex::Frontend::Lexer.new("@@@", file: "invalids.y")
    document, diagnostics = lexer.tokenize_document_recovering(max_diagnostics: 2)

    assert_equal 2, diagnostics.length
    assert_equal "@@@", document.render
    invalid_segments = document.cst.segments.count { |segment| segment.kind == :invalid }
    assert_equal 1, invalid_segments
    assert_raises(ArgumentError) do
      Ibex::Frontend::Lexer.new("@").tokenize_document_recovering(max_diagnostics: 0)
    end
  end

  def test_requested_limit_relexes_without_unbounded_initial_collection
    parser = Ibex::Frontend::Parser.new("@" * 25, file: "many.y")
    result = parser.parse_with_diagnostics(max_diagnostics: 25)

    assert_equal 25, result.diagnostics.length
    assert(result.diagnostics.all? { |diagnostic| diagnostic.phase == :lexical })
    assert_equal((1..25).to_a, result.diagnostics.map { |diagnostic| diagnostic.location.column })
  end

  def test_token_array_input_can_recover_but_has_no_source_document
    tokens = Ibex::Frontend::Lexer.new(MULTIPLE_ERRORS, file: "tokens.y").tokenize
    result = Ibex::Frontend::Parser.new(tokens).parse_with_diagnostics
    lines = result.diagnostics.map { |diagnostic| diagnostic.location.line }

    assert_equal [2, 5], lines
    assert_equal %w[broken later], result.ast.rules.map(&:lhs)
    assert_nil result.document
  end

  def test_results_are_deterministic_and_deduplicated
    results = 2.times.map do
      Ibex::Frontend::Parser.new(MULTIPLE_ERRORS, file: "stable.y").parse_with_diagnostics
    end
    serialized = results.map { |result| result.diagnostics.map(&:to_h) }

    assert_equal serialized.first, serialized.last
    keys = results.first.diagnostics.map do |diagnostic|
      [diagnostic.phase, diagnostic.location.to_h, diagnostic.message]
    end
    assert_equal keys.uniq, keys
  end

  def test_nested_group_recovery_uses_only_the_outer_alternative_boundary
    source = <<~GRAMMAR
      class P
      pragma extended
      rule
      broken: (A | ,) | B
      later: C
      end
    GRAMMAR
    result = Ibex::Frontend::Parser.new(source, file: "nested.y").parse_with_diagnostics

    assert_equal 1, result.diagnostics.length
    assert_equal 4, result.diagnostics.first.location.line
    assert_equal %w[broken later], result.ast.rules.map(&:lhs)
    assert_equal ["B"], result.ast.rules.first.alternatives.first.items.map(&:name)
  end

  def test_strict_parse_is_unchanged_after_a_diagnostic_parse
    parser = Ibex::Frontend::Parser.new(MULTIPLE_ERRORS, file: "strict.y")
    parser.parse_with_diagnostics
    error = assert_raises(Ibex::Error) { parser.parse }

    assert_equal "strict.y:2:8: expected integer, got nope", error.message
  end

  def test_strict_syntax_failure_is_repeat_deterministic
    parser = Ibex::Frontend::Parser.new(MULTIPLE_ERRORS, file: "repeated.y")
    first = assert_raises(Ibex::Error) { parser.parse }
    second = assert_raises(Ibex::Error) { parser.parse }

    assert_equal first.message, second.message
    assert_equal "repeated.y:2:8: expected integer, got nope", second.message
  end

  def test_diagnostic_defensively_copies_and_freezes_its_location
    file = +"mutable.y"
    location = Ibex::Frontend::Location.new(file: file, line: 2, column: 3)
    diagnostic = Ibex::Frontend::Diagnostic.new(
      code: "frontend.syntax_error", phase: :syntax, message: "broken", location: location
    )

    file.replace("changed.y")
    location.line = 99
    assert_equal({ file: "mutable.y", line: 2, column: 3 }, diagnostic.location.to_h)
    assert_predicate diagnostic.location, :frozen?
    assert_predicate diagnostic.location.file, :frozen?
  end

  def test_invalid_utf8_is_one_lexical_diagnostic_without_a_document
    parser = Ibex::Frontend::Parser.new("\xFF".b, file: "invalid.y")
    error = assert_raises(Ibex::Error) { parser.parse }
    document_error = assert_raises(Ibex::Error) { parser.parse_document }
    result = parser.parse_with_diagnostics

    assert_equal "invalid.y: input must be valid UTF-8", error.message
    assert_equal error.message, document_error.message
    assert_instance_of Ibex::Frontend::GeneratedParser, parser.implementation
    assert_equal 1, result.diagnostics.length
    assert_equal "frontend.lexical_error", result.diagnostics.first.code
    assert_nil result.ast
    assert_nil result.document
  end

  def test_unterminated_opaque_source_is_preserved
    source = "class P\nrule\nstart: TOKEN { text = <<~TEXT\nvalue\n"
    parser = Ibex::Frontend::Parser.new(source, file: "unterminated[1].y")
    strict_error = assert_raises(Ibex::Error) { parser.parse }
    result = parser.parse_with_diagnostics
    diagnostic = result.diagnostics.first

    assert_equal "unterminated[1].y:3:23: unterminated heredoc TEXT", strict_error.message
    assert_equal :lexical, diagnostic.phase
    assert_equal "unterminated heredoc TEXT", diagnostic.message
    assert_equal({ file: "unterminated[1].y", line: 3, column: 23 }, diagnostic.location.to_h)
    assert_equal 14, diagnostic.span.start.column
    assert_equal source, result.document.render
    assert_nil result.document.ast
  end
end
