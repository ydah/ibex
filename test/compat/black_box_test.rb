# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

class BlackBoxCompatibilityTest < Minitest::Test
  RUNNER = <<~RUBY
    load ARGV.fetch(0)
    parser = Object.const_get(ARGV.fetch(1)).new
    tokens = eval(ARGV.fetch(2))
    puts parser.parse_tokens(tokens).inspect
  RUBY

  def setup
    skip "racc command is not installed" unless system("racc", "--version", out: File::NULL, err: File::NULL)
  end

  def test_calculator_results_match
    source = File.read(File.expand_path("../fixtures/compat/calculator.y", __dir__))
    compare_result(source, "CompatCalc", [[:NUM, 2], ["+", nil], [:NUM, 3], ["*", nil], [:NUM, 4]])
  end

  def test_empty_rules_string_tokens_convert_and_no_result_var_match
    compare_result(<<~GRAMMAR, "CompatList", [[:ITEM, "a"], [",", nil], [:ITEM, "b"]])
      class CompatList
      rule
      start: items
      items: items ',' ITEM { result = val[0] + [val[2]] }
           | ITEM { result = [val[0]] }
           | { result = [] }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR

    compare_result(<<~GRAMMAR, "CompatConvert", [[:number, "42"]])
      class CompatConvert
      options no_result_var
      convert
      NUM ':number'
      end
      rule
      start: NUM { val[0].to_i }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
  end

  def test_inline_actions_match
    compare_result(<<~GRAMMAR, "CompatInline", [[:A, 3], [:B, 5]])
      class CompatInline
      rule
      start: A { result = 6 } B { result = val[1] + val[2] }
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
  end

  def test_dangling_else_conflict_count_matches
    source = <<~GRAMMAR
      class CompatDangling
      token IF THEN ELSE ID
      expect 1
      rule
      stmt: IF expr THEN stmt
          | IF expr THEN stmt ELSE stmt
          | ID
      expr: ID
      end
    GRAMMAR
    with_compiled_parsers(source) do |_racc_parser, _ibex_parser, racc_errors, ibex_errors|
      assert_equal conflict_count(racc_errors), conflict_count(ibex_errors)
    end
  end

  def test_large_generated_grammar_matches
    rules = (0...500).map { |index| "n#{index}: #{index == 499 ? 'TOKEN' : "n#{index + 1}"}" }
    source = <<~GRAMMAR
      class CompatLarge
      rule
      start: n0
      #{rules.join("\n")}
      end
      ---- inner
      def parse_tokens(tokens) = (@tokens = tokens; do_parse)
      def next_token = @tokens.shift
    GRAMMAR
    compare_result(source, "CompatLarge", [[:TOKEN, 9]])
  end

  private

  def compare_result(source, class_name, tokens)
    with_compiled_parsers(source) do |racc_parser, ibex_parser, _racc_errors, _ibex_errors|
      racc_result = run_parser(racc_parser, class_name, tokens, include_ibex: false)
      ibex_result = run_parser(ibex_parser, class_name, tokens, include_ibex: true)
      assert_equal racc_result, ibex_result
    end
  end

  def with_compiled_parsers(source)
    Dir.mktmpdir("ibex-compat") do |directory|
      grammar = File.join(directory, "grammar.y")
      racc_parser = File.join(directory, "racc_parser.rb")
      ibex_parser = File.join(directory, "ibex_parser.rb")
      File.write(grammar, source)
      _out, racc_errors, racc_status = Open3.capture3("racc", "-o", racc_parser, grammar)
      _out, ibex_errors, ibex_status = Open3.capture3(RbConfig.ruby, "-Ilib", "bin/ibex", "-o", ibex_parser, grammar,
                                                      chdir: File.expand_path("../..", __dir__))
      assert racc_status.success?, racc_errors
      assert ibex_status.success?, ibex_errors
      yield racc_parser, ibex_parser, racc_errors, ibex_errors
    end
  end

  def run_parser(path, class_name, tokens, include_ibex:)
    arguments = [RbConfig.ruby]
    arguments << "-I#{File.expand_path('../../lib', __dir__)}" if include_ibex
    output, errors, status = Open3.capture3(*arguments, "-e", RUNNER, path, class_name, tokens.inspect)
    assert status.success?, errors
    output
  end

  def conflict_count(errors)
    match = errors.match(%r{(\d+) shift/reduce})
    match ? Integer(match[1], 10) : 0
  end
end
