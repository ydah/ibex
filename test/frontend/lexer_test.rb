# frozen_string_literal: true

require_relative "../test_helper"

class LexerTest < Minitest::Test
  def tokenize(source)
    Ibex::Frontend::Lexer.new(source, file: "fixture.y").tokenize
  end

  def actions(source)
    tokenize("class P\nrule\nx : X { #{source} }\nend\n").select { |token| token.type == :action }.map(&:value)
  end

  def test_tokenizes_declarations_rules_comments_and_locations
    source = <<~GRAMMAR
      class Demo::Parser < Base # comment
      token INT '+' /* block */
      rule
      expr : INT | { result = 0 } ;
      end
    GRAMMAR
    tokens = tokenize(source)
    expected_types = %i[
      identifier identifier scope identifier < identifier identifier identifier literal identifier identifier
      : identifier | action ; identifier eof
    ]
    assert_equal expected_types, tokens.map(&:type)
    int = tokens.find { |token| token.value == "INT" }
    assert_equal({ file: "fixture.y", line: 2, column: 7 }, int.location.to_h)
  end

  def test_preserves_braces_inside_ruby_constructs
    cases = [
      's = "}"', "h = { a: 1 }", "r = /}/", "# } comment\nresult = 1", "s = %q(})", "c = ?}"
    ]
    cases.each { |code| assert_equal [" #{code} "], actions(code) }
  end

  def test_handles_nested_string_interpolation
    code = "s = \"\#{ { value: \"}\" } }\"; result = s"
    assert_equal [" #{code} "], actions(code)
  end

  def test_handles_basic_heredoc
    source = "text = <<~TEXT\n}\nTEXT\nresult = text"
    assert_equal [" #{source} "], actions(source)
  end

  def test_rejects_unsupported_heredoc_with_location
    error = assert_raises(Ibex::Error) { actions("text = <<~'TEXT'\nvalue\nTEXT") }
    assert_match(/fixture\.y:3:\d+: quoted heredoc identifiers are not supported/, error.message)
  end

  def test_emits_duplicate_user_code_blocks_in_order
    tokens = tokenize("class P\nrule\nx:\nend\n---- header\nA\n---- inner\nB\n---- header\nC\n")
    blocks = tokens.select { |token| token.type == :user_code }.map(&:value)
    assert_equal [{ name: "header", code: "A\n" }, { name: "inner", code: "B\n" },
                  { name: "header", code: "C\n" }], blocks
  end

  def test_reports_unterminated_constructs_with_location
    error = assert_raises(Ibex::Error) { tokenize("class P\nrule\nx: X { 'oops }\n") }
    assert_match(/fixture\.y:3:8: unterminated ' string/, error.message)

    error = assert_raises(Ibex::Error) { tokenize("class P\n/* never") }
    assert_equal "fixture.y:2:1: unterminated block comment", error.message
  end
end
