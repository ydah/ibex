# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "json"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIFuzzReduceTest < Minitest::Test
  def test_fuzz_and_reduce_help_do_not_require_inputs
    %w[fuzz reduce samples].each do |command|
      output = StringIO.new

      assert_equal 0, Ibex::CLI.start([command, "--help"], stdout: output, stderr: StringIO.new)
      assert_includes output.string, "Usage: ibex #{command}"
    end
  end

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
      assert_fuzz_schema(report)
    end
  end

  def test_fuzz_text_format_states_the_bounded_result_is_not_a_proof
    with_grammar do |path|
      output = StringIO.new
      status = Ibex::CLI.start(
        ["fuzz", "--count=1", "--format=text", path],
        stdout: output, stderr: StringIO.new
      )

      assert_equal 0, status
      assert_includes output.string, "result=no_difference_within_bounds"
      assert_includes output.string, "not a proof of equivalence"
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
      assert_reduce_schema(report)
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
      assert_fuzz_schema(report)
    end
  end

  def test_external_fuzzing_requires_the_target_runtime_configuration
    with_grammar do |path|
      errors = StringIO.new
      status = Ibex::CLI.start(
        ["fuzz", "--count=1", "--against=#{RbConfig.ruby}", path],
        stdout: StringIO.new, stderr: errors
      )

      assert_equal 1, status
      assert_includes errors.string, "--against requires --against-runtime"
    end
  end

  def test_external_fuzzing_reports_target_timeout_as_budget_exhaustion
    Dir.mktmpdir("ibex-fuzz-timeout") do |directory|
      checker = File.join(directory, "slow.rb")
      File.write(checker, "sleep 10\n")
      with_grammar do |path|
        output = StringIO.new
        status = Ibex::CLI.start(
          [
            "fuzz", "--count=1", "--against=#{RbConfig.ruby} #{checker}",
            "--against-runtime=slow-test", "--against-timeout=1", path
          ],
          stdout: output, stderr: StringIO.new
        )
        report = JSON.parse(output.string)

        assert_equal 2, status
        assert_equal "budget_exhausted", report.fetch("result")
        assert_includes report.dig("budget", "message"), "timeout"
        assert_equal "slow-test", report.dig("external", "target_runtime")
        assert_fuzz_schema(report)
      end
    end
  end

  def test_reduce_supports_a_human_readable_text_report
    Dir.mktmpdir("ibex-reduce-text") do |directory|
      input = File.join(directory, "tokens.json")
      checker = File.join(directory, "checker.rb")
      File.write(input, JSON.generate(%w[noise BAD]))
      File.write(checker, "require 'json'\nexit(JSON.parse(STDIN.read).include?('BAD') ? 1 : 0)\n")
      output = StringIO.new

      status = Ibex::CLI.start(
        ["reduce", "--command=#{RbConfig.ruby} #{checker}", "--format=text", input],
        stdout: output, stderr: StringIO.new
      )

      assert_equal 0, status
      assert_includes output.string, "result=minimized"
      assert_includes output.string, 'minimized=["BAD"]'
    end
  end

  def test_fuzz_automatically_minimizes_and_atomically_saves_a_regression
    Dir.mktmpdir("ibex-fuzz-regression") do |directory|
      checker = File.join(directory, "reject.rb")
      regressions = File.join(directory, "regressions")
      File.write(checker, "STDIN.read\nexit 1\n")
      with_grammar do |path|
        status, report = run_mismatching_fuzz(path, checker, regressions)
        assert_saved_fuzz_regression(status, report, regressions)
      end
    end
  end

  def test_fuzz_reports_an_incomplete_automatic_reduction_when_its_budget_is_exhausted
    Dir.mktmpdir("ibex-fuzz-reduction-budget") do |directory|
      checker = File.join(directory, "reject.rb")
      File.write(checker, "STDIN.read\nexit 1\n")
      with_grammar("class FuzzCLI\nrule\nstart: ITEM ITEM ITEM ITEM\nend\n") do |path|
        output = StringIO.new
        status = Ibex::CLI.start(
          [
            "fuzz", "--count=1", "--against=#{RbConfig.ruby} #{checker}",
            "--against-runtime=test-ruby-#{RUBY_VERSION}",
            "--max-reduction-trials=1", "--no-save-regression", path
          ],
          stdout: output, stderr: StringIO.new
        )
        report = JSON.parse(output.string)

        assert_equal 1, status
        assert_equal false, report.dig("mismatch", "reduction", "complete")
        assert_equal 1, report.dig("mismatch", "reduction", "trials")
        assert_nil report.dig("mismatch", "regression")
      end
    end
  end

  private

  def run_mismatching_fuzz(path, checker, regressions)
    output = StringIO.new
    status = Ibex::CLI.start(
      [
        "fuzz", "--count=1", "--seed=9", "--against=#{RbConfig.ruby} #{checker}",
        "--against-runtime=test-ruby-#{RUBY_VERSION}",
        "--regression-dir=#{regressions}", path
      ],
      stdout: output, stderr: StringIO.new
    )
    [status, JSON.parse(output.string)]
  end

  def assert_saved_fuzz_regression(status, report, regressions)
    saved_path = report.dig("mismatch", "regression", "path")
    saved = JSON.parse(File.binread(saved_path))
    schema = JSON.parse(File.binread(File.expand_path("../schema/fuzz-regression-v1.schema.json", __dir__)))

    assert_equal 1, status
    assert_equal ["ITEM"], report.dig("mismatch", "minimized_tokens")
    assert_equal true, report.dig("mismatch", "reduction", "complete")
    assert_equal 9, saved.fetch("seed")
    assert_equal ["ITEM"], saved.fetch("minimized_tokens")
    assert_equal "test-ruby-#{RUBY_VERSION}", saved.dig("external", "target_runtime")
    assert_equal "test-ruby-#{RUBY_VERSION}", report.dig("external", "target_runtime")
    assert_empty JSONSchemer.schema(schema).validate(saved).to_a
    assert_fuzz_schema(report)
    assert_equal Digest::SHA256.file(saved_path).hexdigest, report.dig("mismatch", "regression", "sha256")
    assert_equal [saved_path], Dir.glob(File.join(regressions, "*.json"))
  end

  def assert_reduce_schema(report)
    schema_path = File.expand_path("../schema/reduce-v2.schema.json", __dir__)
    schema = JSON.parse(File.binread(schema_path))
    assert_empty JSONSchemer.schema(schema).validate(report).to_a
  end

  def assert_fuzz_schema(report)
    schema_path = File.expand_path("../schema/fuzz-v1.schema.json", __dir__)
    schema = JSON.parse(File.binread(schema_path))
    assert_empty JSONSchemer.schema(schema).validate(report).to_a
  end

  def with_grammar(source = "class FuzzCLI\nrule\nstart: ITEM | ITEM ',' start\nend\n")
    Dir.mktmpdir("ibex-fuzz") do |directory|
      path = File.join(directory, "grammar.y")
      File.write(path, source)
      yield path
    end
  end
end
