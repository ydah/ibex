# frozen_string_literal: true

require_relative "../test_helper"

class CSTGreenTest < Minitest::Test
  def test_token_widths_and_source_are_byte_exact
    leading = trivia(" ", :whitespace)
    trailing = trivia("\n", :newline)
    token = Ibex::Runtime::CST::GreenToken.new(
      kind: 2, text: "é", leading: [leading], trailing: [trailing]
    )

    assert_equal 4, token.full_width
    assert_equal 1, token.leading_width
    assert_equal 1, token.trailing_width
    assert_equal " é\n".b, token.to_source
    assert_predicate token, :frozen?
    assert_predicate token.leading, :frozen?
  end

  def test_node_derives_trim_widths_flags_and_descendant_count
    zero = Ibex::Runtime::CST::GreenToken.missing(kind: kind(:missing_token), expected_kind: 2)
    left = token(" a", leading: " ")
    right = token("b ", trailing: " ")
    node = Ibex::Runtime::CST::GreenNode.new(kind: 4, children: [zero, left, right])

    assert_equal 4, node.full_width
    assert_equal 1, node.leading_width
    assert_equal 1, node.trailing_width
    assert_equal 4, node.descendant_count
    assert_predicate node.flags & Ibex::Runtime::CST::Flags::CONTAINS_MISSING, :positive?
    assert_equal " ab ".b, node.to_source
  end

  def test_all_zero_width_node_has_zero_trim_widths
    missing = Ibex::Runtime::CST::GreenToken.missing(kind: kind(:missing_token), expected_kind: 2)
    node = Ibex::Runtime::CST::GreenNode.new(kind: 4, children: [missing])

    assert_equal 0, node.full_width
    assert_equal 0, node.leading_width
    assert_equal 0, node.trailing_width
  end

  def test_cache_is_transparent_and_excludes_large_nodes
    cache = Ibex::Runtime::CST::NodeCache.new
    first = Ibex::Runtime::CST::GreenToken.new(kind: 2, text: "x")
    second = Ibex::Runtime::CST::GreenToken.new(kind: 2, text: "x")

    assert_same cache.intern_token(first), cache.intern_token(second)

    children = Array.new(4) { first }
    large_a = Ibex::Runtime::CST::GreenNode.new(kind: 4, children: children)
    large_b = Ibex::Runtime::CST::GreenNode.new(kind: 4, children: children)
    refute_same cache.intern_node(large_a), cache.intern_node(large_b)
    assert_equal large_a.to_source, large_b.to_source
  end

  def test_builder_preserves_error_bytes_and_finishes_source_file
    builder = Ibex::Runtime::CST::GreenBuilder.new(kinds: kinds)
    builder.token(2, "a")
    builder.lexical_error("?")
    error = builder.absorb_into_error(2)
    builder.node(4, 1)
    eof = Ibex::Runtime::CST::GreenToken.new(kind: 0, text: "", leading: [trivia("\n", :newline)])
    root = builder.finish_source_file(eof)

    assert_equal "a?\n".b, root.to_source
    assert_equal kind(:source_file), root.kind
    assert_predicate root.flags & Ibex::Runtime::CST::Flags::CONTAINS_ERROR, :positive?
    assert_equal 2, root.children.length
    assert_equal kind(:error_node), error.kind
  end

  def test_green_tree_is_ractor_shareable
    skip "Ractor shareability is unavailable" unless defined?(Ractor) && Ractor.respond_to?(:shareable?)

    builder = Ibex::Runtime::CST::GreenBuilder.new(kinds: kinds)
    builder.token(2, "x")
    builder.node(4, 1)
    root = builder.finish_source_file(Ibex::Runtime::CST::GreenToken.new(kind: 0, text: ""))

    assert Ractor.shareable?(root)
  end

  private

  def kind_metadata
    @kind_metadata ||= begin
      source = <<~GRAMMAR
        class GreenParser
        pragma cst
        token TOKEN
        rule
        start: TOKEN
        end
      GRAMMAR
      ast = Ibex::Frontend::Parser.new(source, file: "green.y").parse
      grammar = Ibex::Normalizer.new(ast).normalize
      Ibex::Codegen::CSTMetadata.new(grammar).build
    end
  end

  def kinds
    @kinds ||= Ibex::Runtime::CST::Kind.new(kind_metadata.fetch(:kinds))
  end

  def kind(name)
    kinds.fetch(name)
  end

  def trivia(text, name)
    Ibex::Runtime::CST::GreenTrivia.new(kind: kind(name), text: text)
  end

  def token(text, leading: "", trailing: "")
    Ibex::Runtime::CST::GreenToken.new(
      kind: 2, text: text.delete_prefix(leading).delete_suffix(trailing),
      leading: leading.empty? ? [] : [trivia(leading, :whitespace)],
      trailing: trailing.empty? ? [] : [trivia(trailing, :whitespace)]
    )
  end
end
