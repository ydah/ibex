# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/lsp"

class LSPPositionCodecTest < Minitest::Test
  def test_converts_ascii_astral_and_combining_characters
    source = "a😀e\u0301z\n"
    codec = Ibex::LSP::PositionCodec.new(source)

    assert_equal({ "line" => 0, "character" => 0 }, codec.position(0))
    assert_equal({ "line" => 0, "character" => 1 }, codec.position(1))
    assert_equal({ "line" => 0, "character" => 3 }, codec.position(5))
    assert_equal({ "line" => 0, "character" => 5 }, codec.position(8))
    assert_equal 5, codec.byte_offset("line" => 0, "character" => 3)
    assert_equal 8, codec.byte_offset("line" => 0, "character" => 5)
  end

  def test_excludes_crlf_and_rejects_invalid_positions
    codec = Ibex::LSP::PositionCodec.new("a😀\r\nb\n")

    assert_equal 5, codec.byte_offset("line" => 0, "character" => 3)
    assert_equal({ "line" => 1, "character" => 0 }, codec.position(7))
    assert_raises(ArgumentError) { codec.byte_offset("line" => 0, "character" => 2) }
    assert_raises(ArgumentError) { codec.byte_offset("line" => 0, "character" => 4) }
    assert_raises(ArgumentError) { codec.byte_offset("line" => 9, "character" => 0) }
    assert_raises(ArgumentError) { codec.position(6) }
  end

  def test_builds_lsp_ranges_from_frontend_spans
    source = "# 😀\n"
    document = Ibex::Frontend::Lexer.new(source, file: "emoji.y").tokenize_document
    span = document.span(2, 6)

    assert_equal(
      { "start" => { "line" => 0, "character" => 2 }, "end" => { "line" => 0, "character" => 4 } },
      Ibex::LSP::PositionCodec.new(source).range(span)
    )
  end
end
