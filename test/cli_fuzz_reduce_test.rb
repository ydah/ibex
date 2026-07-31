# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIFuzzReduceTest < Minitest::Test
  def test_fuzz_reports_declared_bounds_and_no_difference
    with_grammar do |path|
      output = StringIO.new
      status = Ibex::CLI.start(
        ["fuzz", "--count=10", "--seed=9", "--coverage-guided", "--max-tokens=7", path],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 0, status
      assert_equal "fuzz", report.fetch("ibex_report")
      assert_equal "no_difference_within_bounds", report.fetch("result")
      assert_equal 10, report.fetch("generated_sentences")
      assert_equal 7, report.fetch("bounds").fetch("max_tokens")
    end
  end

  def test_reduce_minimizes_json_tokens_through_an_explicit_subprocess
    Dir.mktmpdir("ibex-reduce") do |directory|
      input = File.join(directory, "tokens.json")
      checker = File.join(directory, "checker.rb")
      File.write(input, JSON.generate(%w[noise BAD more noise]))
      File.write(checker, "require 'json'\nexit(JSON.parse(STDIN.read).include?('BAD') ? 1 : 0)\n")
      output = StringIO.new

      status = Ibex::CLI.start(
        ["reduce", "--command=#{RbConfig.ruby} #{checker}", input],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 0, status
      assert_equal ["BAD"], report.fetch("minimized")
      assert report.fetch("complete")
      assert_equal true, report.fetch("bounded")
    end
  end

  def test_fuzz_distinguishes_budget_exhaustion_from_a_difference
    with_grammar do |path|
      output = StringIO.new
      status = Ibex::CLI.start(
        ["fuzz", "--count=1", "--max-actions=1", path],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 2, status
      assert_equal "budget_exhausted", report.fetch("result")
      assert_match(/exceeded/, report.fetch("budget").fetch("message"))
    end
  end

  private

  def with_grammar
    Dir.mktmpdir("ibex-fuzz") do |directory|
      path = File.join(directory, "grammar.y")
      File.write(path, "class FuzzCLI\nrule\nstart: ITEM | ITEM ',' start\nend\n")
      yield path
    end
  end
end
