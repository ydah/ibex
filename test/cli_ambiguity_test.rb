# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIAmbiguityTest < Minitest::Test
  AMBIGUOUS = <<~GRAMMAR
    class Ambiguous
    token IF THEN ELSE ID
    expect 1
    rule
    statement: IF expression THEN statement
             | IF expression THEN statement ELSE statement
             | ID
    expression: ID
    end
  GRAMMAR

  UNAMBIGUOUS = <<~GRAMMAR
    class Unambiguous
    token VALUE
    rule
    start: VALUE
    end
  GRAMMAR

  LALR_ONLY_CONFLICT = <<~GRAMMAR
    class LalrOnly
    rule
    start: first 'a' 'd'
         | second 'b' 'd'
         | first 'b' 'e'
         | second 'a' 'e'
    first: 'c'
    second: 'c'
    end
  GRAMMAR

  def test_reports_an_ambiguous_sentence_and_fails_the_check
    with_grammar(AMBIGUOUS) do |path|
      result = invoke(["check", "--ambiguity", path])

      assert_equal 1, result.fetch(:status)
      assert_includes result.fetch(:stdout), "Result: ambiguous"
      assert_includes result.fetch(:stdout), "IF ID THEN IF ID THEN ID ELSE ID"
      assert_empty result.fetch(:stderr)
    end
  end

  def test_succeeds_when_no_ambiguity_is_found_within_the_bounds
    with_grammar(UNAMBIGUOUS) do |path|
      result = invoke(["check", "--ambiguity", path])

      assert_equal 0, result.fetch(:status)
      assert_includes result.fetch(:stdout), "Result: no_ambiguity_found_within_bounds"
      assert_includes result.fetch(:stdout), "Conflicts: 0"
    end
  end

  def test_configuration_exhaustion_is_distinct_and_machine_readable
    with_grammar(AMBIGUOUS) do |path|
      result = invoke(
        ["check", "--ambiguity", "--max-configurations=1", "--format=json", path]
      )
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 2, result.fetch(:status)
      assert_equal "ambiguity", document.fetch("ibex_check")
      assert_equal "inconclusive", document.fetch("status")
      assert_equal 1, document.dig("search", "max_configurations")
      assert_operator document.dig("summary", "configuration_budget_exhausted"), :>, 0
      complete_entries = document.fetch("conflicts").all? { |entry| entry.key?("explored_configurations") }
      assert complete_entries
    end
  end

  def test_a_nonunifying_lalr_conflict_is_not_reported_as_ambiguity
    with_grammar(LALR_ONLY_CONFLICT) do |path|
      result = invoke(["check", "--ambiguity", "--format=json", path])
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 0, result.fetch(:status)
      assert_equal "no_ambiguity_found_within_bounds", document.fetch("status")
      assert_operator document.dig("summary", "conflicts"), :>, 0
      assert_equal 0, document.dig("summary", "ambiguous")
    end
  end

  def test_requires_the_mode_and_positive_budgets
    missing = invoke(["check"])
    assert_equal 1, missing.fetch(:status)
    assert_equal "(cli):1:1: check command requires --ambiguity\n", missing.fetch(:stderr)

    %w[--max-tokens=0 --max-configurations=-1].each do |option|
      result = invoke(["check", "--ambiguity", option])
      assert_equal 1, result.fetch(:status)
      assert_match(/must be positive/, result.fetch(:stderr))
    end
  end

  private

  def with_grammar(source)
    Dir.mktmpdir("ibex-ambiguity") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      yield path
    end
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end
end
