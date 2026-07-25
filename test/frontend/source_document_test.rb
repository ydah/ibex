# frozen_string_literal: true

require_relative "../test_helper"

class SourceDocumentTest < Minitest::Test
  LOSSLESS_SOURCE = <<~GRAMMAR
    class Demo::Parser # grammar comment
    token WORD /* token comment */
    rule
    value: WORD { result = val[0] }
    end
    ---- header
    # frozen_string_literal: true
    ---- inner
    def helper = "😀"
    ---- header
    HEADER = :second
  GRAMMAR
  private_constant :LOSSLESS_SOURCE

  def test_parse_document_preserves_source_ast_and_ir
    parser = Ibex::Frontend::Parser.new(LOSSLESS_SOURCE, file: "lossless.y")
    document = parser.parse_document
    ordinary_ast = Ibex::Frontend::Parser.new(LOSSLESS_SOURCE, file: "lossless.y").parse

    assert_same document.ast, parser.parse
    assert_same document, parser.parse_document
    assert_equal LOSSLESS_SOURCE, document.render
    assert_equal LOSSLESS_SOURCE, document.cst.render
    assert_equal ordinary_ast.to_h, document.ast.to_h

    ordinary_ir = Ibex::Normalizer.new(ordinary_ast).normalize
    document_ir = Ibex::Normalizer.new(document.ast).normalize
    assert_equal Ibex::IR::Serialize.dump(ordinary_ir), Ibex::IR::Serialize.dump(document_ir)

    ast_first_parser = Ibex::Frontend::Parser.new(LOSSLESS_SOURCE, file: "lossless.y")
    assert_same ast_first_parser.parse, ast_first_parser.parse_document.ast
  end

  def test_cst_classifies_trivia_actions_and_duplicate_user_code
    document = Ibex::Frontend::Parser.new(LOSSLESS_SOURCE, file: "lossless.y").parse_document
    kinds = document.cst.map(&:kind)

    assert_operator kinds.count(:newline), :>, 0
    assert_equal 1, kinds.count(:line_comment)
    assert_equal 1, kinds.count(:block_comment)
    assert_equal 3, kinds.count(:user_code_marker)
    assert_equal 3, kinds.count(:user_code_body)
    assert_equal 1, kinds.count(:action)
  end

  def test_positions_are_byte_based_and_round_trip_crlf_and_supplementary_characters
    source = "class P\r\n# 😀 comment\r\nrule\r\nvalue: WORD\r\nend\r\n"
    document = Ibex::Frontend::Parser.new(source, file: "unicode.y").parse_document

    offset = 0
    source.each_char do |character|
      position = document.position_at(offset)
      assert_equal offset, document.byte_offset_at(position.line, position.column)
      offset += character.bytesize
    end
    position = document.position_at(source.bytesize)
    assert_equal source.bytesize, document.byte_offset_at(position.line, position.column)

    emoji_offset = source.b.index("😀".b)
    emoji_position = document.position_at(emoji_offset)
    assert_equal [2, 3], [emoji_position.line, emoji_position.column]
    assert_raises(ArgumentError) { document.position_at(emoji_offset + 1) }
  end

  def test_token_spans_slice_source_without_changing_token_serialization
    source = "class P\r\n# 😀 comment\r\nrule\r\nvalue: WORD\r\nend\r\n"
    document = Ibex::Frontend::Parser.new(source, file: "unicode.y").parse_document
    word = document.tokens.find { |token| token.value == "WORD" }

    assert_equal "WORD", document.slice(word.span)
    assert_equal source.b.index("WORD"), word.span.start_byte
    assert_equal({ file: "unicode.y", line: 4, column: 8 }, word.location.to_h)
    assert_equal %i[type value location], word.to_h.keys
  end

  def test_actions_keep_all_supported_heredoc_forms_opaque
    source = <<~'GRAMMAR'
      class P
      rule
      bare: X { text = <<TEXT
      }
      TEXT
      result = text }
      single: X { text = <<-'TEXT'
      }
      TEXT
      result = text }
      double: X { text = <<~"END } MARK"
      #{ { brace: "}" } }
      END } MARK
      result = text }
      command: X { text = <<-`SHELL`
      }
      SHELL
      result = text }
      end
    GRAMMAR
    document = Ibex::Frontend::Parser.new(source, file: "heredocs.y").parse_document
    actions = document.cst.select { |segment| segment.kind == :action }

    assert_equal 4, actions.length
    assert actions.all?(&:opaque?)
    assert_includes actions[0].text, "<<TEXT"
    assert_includes actions[1].text, "<<-'TEXT'"
    assert_includes actions[2].text, '<<~"END } MARK"'
    assert_includes actions[3].text, "<<-`SHELL`"
    assert_equal source, document.render
  end

  def test_segments_and_cst_are_immutable_and_link_to_semantic_tokens
    mutable_source = +"class P\nrule\nvalue: X\nend\n"
    parser = Ibex::Frontend::Parser.new(mutable_source, file: "immutable.y")
    mutable_source.replace("changed")
    document = parser.parse_document
    token_segment = document.cst.find { |segment| segment.token_type == :identifier }

    assert_equal "class P\nrule\nvalue: X\nend\n", document.render
    assert_predicate token_segment, :frozen?
    assert_predicate token_segment.text, :frozen?
    assert_predicate document.cst, :frozen?
    assert_predicate document.cst.segments, :frozen?
    assert_equal token_segment.token_type, document.token_for(token_segment).type
    assert_raises(FrozenError) { token_segment.instance_variable_set(:@kind, :changed) }
    assert_raises(FrozenError) { document.cst.segments << token_segment }
  end

  def test_cst_each_supports_enumerator_and_block_forms
    document = Ibex::Frontend::Lexer.new("class P\n", file: "each.y").tokenize_document
    yielded = document.cst.each { |_segment| nil }

    assert_equal document.cst.segments, document.cst.each.to_a
    assert_same document.cst, yielded
  end

  def test_lexer_document_handles_empty_source_and_eof
    document = Ibex::Frontend::Lexer.new("", file: "empty.y").tokenize_document
    eof = document.tokens.fetch(0)
    eof_segment = document.cst.segments.fetch(0)

    assert_equal "", document.render
    assert_equal :eof, eof.type
    assert_predicate eof.span, :empty?
    assert_equal :eof, eof_segment.kind
    assert_predicate eof_segment.span, :empty?
    assert_same eof, document.token_for(eof_segment)
  end

  def test_tokenize_returns_only_tokens_remaining_after_streaming_reads
    lexer = Ibex::Frontend::Lexer.new("class P\nrule\ns: X\nend\n", file: "stream.y")
    first = lexer.next_token
    remaining = lexer.tokenize

    assert_equal "class", first.value
    assert_equal "P", remaining.first.value
    assert_equal :eof, remaining.last.type
    assert_equal [:eof], lexer.tokenize.map(&:type)

    document = lexer.tokenize_document
    assert_same first, document.tokens.first
    assert_equal 1, document.tokens.map(&:type).count(:eof)
    assert_equal "class P\nrule\ns: X\nend\n", document.render
  end

  def test_invalid_utf8_and_token_only_documents_are_rejected_explicitly
    error = assert_raises(Ibex::Error) do
      Ibex::Frontend::Lexer.new("\xFF".b, file: "invalid.y")
    end
    assert_equal "invalid.y: input must be valid UTF-8", error.message

    tokens = Ibex::Frontend::Lexer.new("class P\nrule\ns: X\nend\n").tokenize
    parser = Ibex::Frontend::Parser.new(tokens)
    assert_raises(ArgumentError) { parser.parse_document }
  end
end
