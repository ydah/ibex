# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIImpactTest < Minitest::Test
  def test_help_does_not_require_input
    output = StringIO.new

    assert_equal 0, Ibex::CLI.start(["impact", "--help"], stdout: output, stderr: StringIO.new)
    assert_includes output.string, "Usage: ibex impact"
  end

  def test_potential_report_matches_schema_and_is_deterministic
    with_grammars("start: pair\npair: value\nvalue: 'x'", "start: pair\npair: value\nvalue: 'x'") do |before, _after|
      first = run_impact(["impact", "--symbol=value", before])
      second = run_impact(["impact", "--symbol=value", before])

      assert_equal 0, first.fetch(:status)
      assert_equal first.fetch(:stdout), second.fetch(:stdout)
      assert_schema(JSON.parse(first.fetch(:stdout)))
    end
  end

  def test_diff_uses_rule_names_as_seeds
    with_grammars("start: A\nother: OLD", "start: A\nother: NEW") do |before, after|
      result = run_impact(["impact", before, after])
      report = JSON.parse(result.fetch(:stdout))

      assert_equal 0, result.fetch(:status)
      assert_equal(["other"], report.fetch("seeds").map { |seed| seed.fetch("symbol") })
    end
  end

  def test_schema_rejects_unknown_top_level_keys
    with_grammars("start: TOKEN", "start: TOKEN") do |before, _after|
      report = JSON.parse(run_impact(["impact", "--symbol=start", before]).fetch(:stdout))
      report["unexpected"] = true

      schema = JSON.parse(File.binread(File.expand_path("../schema/impact-v1.schema.json", __dir__)))
      errors = JSONSchemer.schema(schema).validate(report).to_a
      refute_empty errors
    end
  end

  private

  def run_impact(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    { status: Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr), stdout: stdout.string, stderr: stderr.string }
  end

  def assert_schema(report)
    schema = JSON.parse(File.binread(File.expand_path("../schema/impact-v1.schema.json", __dir__)))
    errors = JSONSchemer.schema(schema).validate(report).to_a
    assert_empty errors, errors.inspect
  end

  def with_grammars(before_rules, after_rules)
    Dir.mktmpdir("ibex-impact") do |directory|
      before = File.join(directory, "before.y")
      after = File.join(directory, "after.y")
      File.binwrite(before, "class P\nrule\n#{before_rules}\nend\n")
      File.binwrite(after, "class P\nrule\n#{after_rules}\nend\n")
      yield before, after
    end
  end
end
