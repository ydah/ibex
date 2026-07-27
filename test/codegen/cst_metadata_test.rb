# frozen_string_literal: true

require_relative "../test_helper"

class CSTMetadataTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class MetadataParser
    pragma extended
    pragma cst
    token NUM PLUS
    rule
    start: expression
    expression: NUM PLUS NUM @node Binary(left, op, right)
              | NUM
    end
  GRAMMAR

  def test_kind_assignment_is_deterministic
    grammar = normalize(SOURCE)

    first = Ibex::Codegen::CSTMetadata.new(grammar, trivia_policy: :attach).build
    second = Ibex::Codegen::CSTMetadata.new(grammar, trivia_policy: :leading).build

    assert_equal first, second
    assert_equal :leading, first.fetch(:trivia_policy)
    assert_equal %w[$eof error NUM PLUS], first.dig(:kinds, :names).first(4)
    assert_equal [0, 4], first.dig(:kinds, :terminal_range)
    assert_equal [4, 6], first.dig(:kinds, :nonterminal_range)
  end

  def test_named_trivia_and_synthetic_intervals_are_stable
    metadata = Ibex::Codegen::CSTMetadata.new(normalize(SOURCE)).build
    kinds = metadata.fetch(:kinds)
    binary = kinds.fetch(:named).fetch("Binary")

    assert_equal 6, binary
    assert_equal 5, kinds.fetch(:named_nonterminals).fetch(binary)
    assert_equal 7, kinds.fetch(:trivia).fetch("whitespace")
    assert_operator kinds.fetch(:synthetic).fetch("lexical_error_token"), :>,
                    kinds.fetch(:trivia).fetch("skipped_tokens")
    assert_equal({ left: 0, op: 1, right: 2 }, symbolize_fields(metadata.fetch(:slots).fetch(1).fetch(:fields)))
  end

  def test_rejects_unknown_trivia_policy
    error = assert_raises(ArgumentError) do
      Ibex::Codegen::CSTMetadata.new(normalize(SOURCE), trivia_policy: :unknown)
    end

    assert_match(/cst_trivia/, error.message)
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "metadata.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def symbolize_fields(fields)
    fields.to_h { |name, index| [name.to_sym, index] }
  end
end
