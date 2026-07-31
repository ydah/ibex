# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"

class AdversarialLimitsTest < Minitest::Test
  FULL = ENV["IBEX_ADVERSARIAL_FULL"] == "1"

  def test_deep_grammar_nesting_stops_with_a_structured_error
    depth = FULL ? 100_000 : 12_000
    source = "class Deep\npragma extended\nrule\nstart: #{'(' * depth} TOKEN #{')' * depth}\nend\n"

    error = assert_raises(Ibex::ResourceLimitError, Ibex::Error) do
      Ibex::Frontend::Parser.new(source, file: "deep.y", mode: :extended).parse
    end
    assert_match(/deep\.y|resource limit/, error.message)
  end

  def test_giant_token_is_processed_without_recursion
    length = FULL ? 10_000_000 : 1_000_000
    source = "a" * length
    tokens = Ibex::Frontend::Lexer.new(source, file: "giant.y").tokenize

    assert_equal 2, tokens.length
    assert_equal source, tokens.first.value
  end

  def test_invalid_utf8_has_a_file_qualified_error
    error = assert_raises(Ibex::Error) do
      Ibex::Frontend::Lexer.new("\xFF".b, file: "invalid.y")
    end

    assert_equal "invalid.y: input must be valid UTF-8", error.message
  end

  def test_large_alternative_set_is_bounded_by_normalization_limits
    count = FULL ? 50_000 : 5_000
    alternatives = Array.new(count) { |index| "TOKEN_#{index}" }.join(" | ")
    source = "class Wide\nrule\nstart: #{alternatives}\nend\n"
    ast = Ibex::Frontend::Parser.new(source, file: "wide.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize

    assert_equal count, grammar.productions.length
  end

  def test_include_cycle_is_rejected_with_the_complete_chain
    Dir.mktmpdir("ibex-cycle") do |directory|
      root = File.join(directory, "root.y")
      first = File.join(directory, "first.y")
      second = File.join(directory, "second.y")
      File.write(root, "class Cycle\ninclude \"first.y\"\nrule\nstart: item\nend\n")
      File.write(first, "fragment\ninclude \"second.y\"\nrule\nitem: TOKEN\nend\n")
      File.write(second, "fragment\ninclude \"first.y\"\nrule\nother: TOKEN\nend\n")

      error = assert_raises(Ibex::Error) { Ibex::Frontend::Resolver.new(root, mode: :extended).resolve }
      assert_includes error.message, "include cycle"
      assert_includes error.message, "first.y"
      assert_includes error.message, "second.y"
    end
  end

  def test_pathological_lexer_pattern_can_be_stopped_as_a_positioned_error
    Dir.mktmpdir("ibex-redos") do |directory|
      path = File.join(directory, "redos.y")
      File.write(path, <<~GRAMMAR)
        class RiskyLexer
        pragma extended
        token ITEM
        lexer
          ITEM /(a+)+$/
        end
        rule
        start: ITEM
        end
      GRAMMAR
      errors = StringIO.new

      status = Ibex::CLI.start(
        ["--mode=extended", "--warnings=error", path],
        stdout: StringIO.new, stderr: errors
      )

      assert_equal 1, status
      assert_includes errors.string, "#{path}:5:3"
      assert_includes errors.string, "excessive backtracking"
      refute File.exist?(File.join(directory, "redos.rb"))
    end
  end
end
