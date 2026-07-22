# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tempfile"

class CLICounterexampleOptionsTest < Minitest::Test
  def test_search_limits_affect_reports
    with_conflicting_grammar do |grammar|
      assert_limited_report(grammar, "--counterexample-max-tokens=8")
      assert_limited_report(grammar, "--counterexample-max-configurations=100")
    end
  end

  def test_search_limits_must_be_positive
    %w[--counterexample-max-tokens --counterexample-max-configurations].each do |option|
      [0, -1].each do |value|
        errors = StringIO.new
        status = Ibex::CLI.start(["#{option}=#{value}"], stdout: StringIO.new, stderr: errors)
        assert_equal 1, status
        assert_equal "(cli):1:1: #{option} must be positive\n", errors.string
      end
    end
  end

  private

  def assert_limited_report(grammar, option)
    Tempfile.create(["limited", ".output"]) do |report|
      errors = StringIO.new
      status = Ibex::CLI.start(
        ["--counterexamples", option, "-O", report.path, grammar.path], stdout: StringIO.new, stderr: errors
      )
      assert_equal 0, status, errors.string
      assert_includes File.read(report.path), "nonunifying witness:"
    end
  end

  def with_conflicting_grammar
    Tempfile.create(["conflicting-grammar", ".y"]) do |grammar|
      grammar.write(<<~GRAMMAR)
        class P
        token IF THEN ELSE ID
        expect 1
        rule
        stmt: IF expr THEN stmt
            | IF expr THEN stmt ELSE stmt
            | ID
        expr: ID
        end
      GRAMMAR
      grammar.flush
      yield grammar
    end
  end
end
