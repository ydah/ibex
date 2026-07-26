# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class CLIGrammarTestsTest < Minitest::Test
  def test_runs_declared_tests_and_reports_tap_like_results
    with_grammar(<<~GRAMMAR) do |path|
      class CLITestParser
      pragma extended
      %test accept "ab"
      %test reject "a"
      rule
      start: 'a' 'b'
      end
      ---- inner
      def parse(source)
        @tokens = source.each_char.map { |character| [character, nil] }
        do_parse
      end
      def next_token = @tokens.shift || false
    GRAMMAR
      output = StringIO.new

      assert_equal 0, Ibex::CLI.start(["test", path], stdout: output, stderr: StringIO.new)
      assert_includes output.string, "ok 1 - accept"
      assert_includes output.string, "ok 2 - reject"
      assert_includes output.string, "2 tests, 0 failures"
    end
  end

  def test_returns_failure_for_a_mismatched_expectation
    with_grammar(<<~GRAMMAR) do |path|
      class CLIFailingTestParser
      pragma extended
      %test reject "a"
      rule
      start: 'a'
      end
      ---- inner
      def parse(source)
        @tokens = source.each_char.map { |character| [character, nil] }
        do_parse
      end
      def next_token = @tokens.shift || false
    GRAMMAR
      output = StringIO.new

      assert_equal 1, Ibex::CLI.start(["test", path], stdout: output, stderr: StringIO.new)
      assert_includes output.string, "not ok 1 - reject"
      assert_includes output.string, "parser accepted the input"
      assert_includes output.string, "1 tests, 1 failures"
    end
  end

  def test_help_does_not_require_a_grammar
    output = StringIO.new

    assert_equal 0, Ibex::CLI.start(%w[test --help], stdout: output, stderr: StringIO.new)
    assert_includes output.string, "Usage: ibex test"
  end

  private

  def with_grammar(source)
    Tempfile.create(["grammar-tests", ".y"]) do |file|
      file.write(source)
      file.flush
      yield file.path
    end
  end
end
