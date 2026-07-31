# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIReduceBudgetsTest < Minitest::Test
  def test_reduce_reports_checker_timeout_as_budget_exhaustion
    Dir.mktmpdir("ibex-reduce-timeout") do |directory|
      input = File.join(directory, "tokens.json")
      checker = File.join(directory, "slow.rb")
      File.write(input, JSON.generate(["BAD"]))
      File.write(checker, "sleep 10\n")
      output = StringIO.new

      status = Ibex::CLI.start(
        ["reduce", "--command=#{RbConfig.ruby} #{checker}", "--timeout=1", input],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 2, status
      assert_equal "budget_exhausted", report.fetch("result")
      assert_equal "subprocess_timeout", report.dig("budget", "kind")
      assert_reduce_schema(report)
    end
  end

  def test_reduce_bounds_input_before_reading_the_complete_file
    Dir.mktmpdir("ibex-reduce-input-budget") do |directory|
      input = File.join(directory, "tokens.json")
      File.write(input, JSON.generate(["BAD"]))
      output = StringIO.new

      status = Ibex::CLI.start(
        ["reduce", "--command=#{RbConfig.ruby} -e 'exit 1'", "--max-input-bytes=1", input],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 2, status
      assert_equal "input_bytes", report.dig("budget", "kind")
      assert_reduce_schema(report)
    end
  end

  def test_reduce_line_mode_can_minimize_a_failing_grammar_fragment
    Dir.mktmpdir("ibex-reduce-lines") do |directory|
      input = File.join(directory, "grammar.y")
      checker = File.join(directory, "checker.rb")
      File.write(input, "header\nBAD_RULE\nfooter\n")
      File.write(checker, "exit(STDIN.read.include?('BAD_RULE') ? 1 : 0)\n")
      output = StringIO.new

      status = Ibex::CLI.start(
        ["reduce", "--mode=lines", "--command=#{RbConfig.ruby} #{checker}", input],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 0, status
      assert_equal ["BAD_RULE\n"], report.fetch("minimized")
      assert_reduce_schema(report)
    end
  end

  def test_reduce_distinguishes_incomplete_minimization_from_a_complete_result
    Dir.mktmpdir("ibex-reduce-trial-budget") do |directory|
      input = File.join(directory, "tokens.json")
      File.write(input, JSON.generate(%w[one two BAD]))
      output = StringIO.new

      status = Ibex::CLI.start(
        ["reduce", "--command=#{RbConfig.ruby} -e 'exit 1'", "--max-trials=1", input],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 2, status
      assert_equal "incomplete", report.fetch("result")
      assert_equal false, report.fetch("complete")
      assert_equal 1, report.fetch("trials")
      assert_reduce_schema(report)
    end
  end

  private

  def assert_reduce_schema(report)
    schema_path = File.expand_path("../schema/reduce-v2.schema.json", __dir__)
    schema = JSON.parse(File.binread(schema_path))
    assert_empty JSONSchemer.schema(schema).validate(report).to_a
  end
end
