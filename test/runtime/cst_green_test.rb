# frozen_string_literal: true

require_relative "../test_helper"
require "ibex/runtime/cst"

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

  def test_cache_interns_token_fields_before_constructing_a_duplicate
    cache = Ibex::Runtime::CST::NodeCache.new
    first = cache.intern_token_fields(kind: 2, text: "x")
    second = cache.intern_token_fields(kind: 2, text: "x")

    assert_same first, second
    assert_equal Ibex::Runtime::CST::GreenToken.new(kind: 2, text: "x"), first
  end

  def test_cache_interns_equivalent_trivia_fields
    cache = Ibex::Runtime::CST::NodeCache.new
    first = cache.intern_trivia_fields(kind: kind(:whitespace), text: " ")
    second = cache.intern_trivia_fields(kind: kind(:whitespace), text: " ")

    assert_same first, second
  end

  def test_cache_enabled_and_disabled_trees_have_identical_structure_source_and_dump
    cached = repeated_root(Ibex::Runtime::CST::NodeCache.new)
    uncached = repeated_root(Ibex::Runtime::CST::NodeCache.new(enabled: false))

    assert_equal cached.green, uncached.green
    assert_equal cached.to_source, uncached.to_source
    assert_equal dump(cached), dump(uncached)
    assert_same cached.tokens.fetch(0).green, cached.tokens.fetch(1).green
    refute_same uncached.tokens.fetch(0).green, uncached.tokens.fetch(1).green
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

  def test_green_tree_can_be_read_concurrently_in_ractors
    skip "Ractor is unavailable" unless defined?(Ractor) && Ractor.respond_to?(:shareable?)

    root = repeated_root(Ibex::Runtime::CST::NodeCache.new).green
    readers = 2.times.map do
      Ractor.new(root) { |green| [green.to_source, green.descendant_count] }
    end

    results = readers.map { |reader| reader.respond_to?(:value) ? reader.value : reader.take }
    assert_equal [["xx", 5], ["xx", 5]], results
  end

  def test_green_layer_loads_without_the_parser
    require "open3"
    require "rbconfig"

    _output, error, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", "-e",
      'require "ibex/runtime/cst/green/builder"; require "ibex/runtime/cst/kind"'
    )

    assert_predicate status, :success?, error
  end

  private

  def repeated_root(cache)
    builder = Ibex::Runtime::CST::GreenBuilder.new(kinds: kinds, cache: cache)
    builder.token(2, "x")
    builder.token(2, "x")
    builder.node(3, 2)
    green = builder.finish_source_file(Ibex::Runtime::CST::GreenToken.new(kind: 0, text: ""))
    Ibex::Runtime::CST::SyntaxNode.new(green: green, kinds: kinds)
  end

  def dump(root)
    Ibex::Runtime::CST::Serialize.dump(
      root,
      grammar_digest: "sha256:#{'0' * 64}",
      table_format: 6,
      state_count: 1,
      production_count: 1
    )
  end

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
