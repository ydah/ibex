# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIEquivTest < Minitest::Test
  def test_equiv_help_does_not_require_inputs
    output = StringIO.new

    assert_equal 0, Ibex::CLI.start(%w[equiv --help], stdout: output, stderr: StringIO.new)
    assert_includes output.string, "Usage: ibex equiv"
  end

  def test_equiv_returns_zero_for_no_difference_and_matches_schema
    with_grammars("start: TOKEN", "start: TOKEN") do |left, right|
      output = StringIO.new

      status = Ibex::CLI.start(["equiv", left, right], stdout: output, stderr: StringIO.new)
      report = JSON.parse(output.string)

      assert_equal 0, status
      assert_equal "no_difference_within_bounds", report.fetch("result")
      assert_schema_valid(report)
    end
  end

  def test_equiv_returns_one_with_a_concrete_counterexample
    with_grammars("start: LEFT", "start: RIGHT") do |left, right|
      output = StringIO.new

      status = Ibex::CLI.start(
        ["equiv", "--samples=1", "--max-tokens=2", left, right],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 1, status
      assert_equal "difference", report.fetch("result")
      refute_empty report.fetch("witness")
      assert_schema_valid(report)
    end
  end

  def test_equiv_returns_two_for_product_budget_exhaustion
    with_grammars("start: TOKEN", "start: wrapper\nwrapper: TOKEN") do |left, right|
      output = StringIO.new

      status = Ibex::CLI.start(
        ["equiv", "--samples=1", "--max-tokens=3", "--max-configurations=1", left, right],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 2, status
      assert_equal "budget_exhausted", report.fetch("result")
      assert_schema_valid(report)
    end
  end

  def test_equiv_accepts_grammar_and_automaton_ir
    Dir.mktmpdir("ibex-equiv-ir") do |directory|
      grammar = normalize("class P\nrule\nstart: TOKEN\nend\n", "input.y")
      automaton = Ibex::LALR::Builder.new(grammar).build
      grammar_path = File.join(directory, "grammar.json")
      automaton_path = File.join(directory, "automaton.json")
      File.binwrite(grammar_path, Ibex::IR::Serialize.dump(grammar))
      File.binwrite(automaton_path, Ibex::IR::Serialize.dump(automaton))

      assert_equal 0, Ibex::CLI.start(
        ["equiv", grammar_path, automaton_path], stdout: StringIO.new, stderr: StringIO.new
      )
    end
  end

  private

  def with_grammars(left_rules, right_rules)
    Dir.mktmpdir("ibex-equiv") do |directory|
      left = File.join(directory, "left.y")
      right = File.join(directory, "right.y")
      File.binwrite(left, "class Left\nrule\n#{left_rules}\nend\n")
      File.binwrite(right, "class Right\nrule\n#{right_rules}\nend\n")
      yield left, right
    end
  end

  def normalize(source, file)
    ast = Ibex::Frontend::Parser.new(source, file: file).parse
    Ibex::Normalizer.new(ast).normalize
  end

  def assert_schema_valid(report)
    path = File.expand_path("../schema/equiv-v1.schema.json", __dir__)
    errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(report).to_a
    assert_empty errors, errors.inspect
  end
end
