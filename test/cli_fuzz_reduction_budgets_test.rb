# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIFuzzReductionBudgetsTest < Minitest::Test
  # Let the initial comparison finish before the stateful checker times out in reduction.
  REDUCTION_TIMEOUT_SECONDS = RUBY_ENGINE == "ruby" ? 1 : 10

  def test_reduction_timeout_is_not_misreported_as_a_nonreproducing_candidate
    Dir.mktmpdir("ibex-fuzz-reduction-timeout") do |directory|
      grammar = File.join(directory, "grammar.y")
      checker = File.join(directory, "checker.rb")
      counter = File.join(directory, "counter")
      File.write(grammar, "class P\nrule\nstart: ITEM\nend\n")
      File.write(checker, checker_source(REDUCTION_TIMEOUT_SECONDS + 10))
      output = StringIO.new

      status = Ibex::CLI.start(
        [
          "fuzz", "--count=1", "--against=#{RbConfig.ruby} #{checker} #{counter}",
          "--against-runtime=stateful-timeout-test",
          "--against-timeout=#{REDUCTION_TIMEOUT_SECONDS}",
          "--no-save-regression", grammar
        ],
        stdout: output, stderr: StringIO.new
      )
      report = JSON.parse(output.string)

      assert_equal 2, status
      assert_equal "budget_exhausted", report.fetch("result")
      assert_equal "reduction", report.dig("budget", "phase")
      assert_includes report.dig("budget", "message"), "timeout"
    end
  end

  private

  def checker_source(sleep_seconds)
    <<~RUBY
      path = ARGV.fetch(0)
      count = File.exist?(path) ? Integer(File.binread(path)) : 0
      File.binwrite(path, (count + 1).to_s)
      sleep #{sleep_seconds} if count.positive?
      exit 1
    RUBY
  end
end
