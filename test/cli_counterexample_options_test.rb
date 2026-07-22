# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLICounterexampleOptionsTest < Minitest::Test
  def test_search_limits_affect_reports
    assert_limited_report("--counterexample-max-tokens=8")
    assert_limited_report("--counterexample-max-configurations=100")
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

  def assert_limited_report(option)
    Dir.mktmpdir("ibex-counterexample-limit") do |directory|
      grammar = File.join(directory, "conflicting.y")
      report = File.join(directory, "conflicting.output")
      File.write(grammar, conflicting_grammar)
      errors = StringIO.new
      status = Ibex::CLI.start([option, grammar], stdout: StringIO.new, stderr: errors)
      assert_equal 0, status, errors.string
      assert_includes File.read(report), "nonunifying witness:"
    end
  end

  def conflicting_grammar
    <<~GRAMMAR
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
  end
end
