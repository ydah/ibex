# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIImpactTest < Minitest::Test
  GALLERY_GRAMMARS = %w[gallery/calc/grammar.y gallery/json/grammar.y].freeze

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

  def test_set_change_gate_is_not_hidden_by_the_display_threshold
    with_grammars("start: value\nvalue: A", "start: value\nvalue: B") do |before, after|
      result = run_impact(["impact", "--severity=critical", "--fail-on=first_change", before, after])
      report = JSON.parse(result.fetch(:stdout))

      assert_equal 1, result.fetch(:status)
      assert_empty report.fetch("symbols")
    end
  end

  def test_new_conflict_is_counted_as_critical
    with_grammars(
      "statement: ID",
      "statement: IF expression THEN statement | IF expression THEN statement ELSE statement | ID\nexpression: ID"
    ) do |before, after|
      report = JSON.parse(run_impact(["impact", before, after]).fetch(:stdout))
      conflicts = report.dig("automaton", "conflicts", "added")

      refute_empty conflicts
      assert_operator report.dig("totals", "critical"), :>=, conflicts.length
    end
  end

  def test_report_is_independent_of_source_directory_and_process_environment
    grammar = "class P\nrule\nstart: pair\npair: value\nvalue: 'x'\nend\n"
    Dir.mktmpdir("ibex-impact-a") do |first_directory|
      Dir.mktmpdir("ibex-impact-b") do |second_directory|
        first_path = File.join(first_directory, "grammar.y")
        second_path = File.join(second_directory, "grammar.y")
        File.binwrite(first_path, grammar)
        File.binwrite(second_path, grammar)
        original = { "LANG" => ENV.fetch("LANG", nil), "TZ" => ENV.fetch("TZ", nil) }
        begin
          ENV["LANG"] = "C"
          ENV["TZ"] = "UTC"
          first = run_impact(["impact", "--symbol=value", first_path])
          ENV["LANG"] = "ja_JP.UTF-8"
          ENV["TZ"] = "Pacific/Auckland"
          second = run_impact(["impact", "--symbol=value", second_path])
        ensure
          original.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
        end

        assert_equal first.fetch(:stdout), second.fetch(:stdout)
      end
    end
  end

  def test_gallery_reports_are_schema_valid_and_deterministic
    GALLERY_GRAMMARS.each do |relative_path|
      path = File.expand_path("../#{relative_path}", __dir__)
      first = run_impact(["impact", path, path])
      second = run_impact(["impact", path, path])

      assert_equal 0, first.fetch(:status), relative_path
      assert_equal first.fetch(:stdout), second.fetch(:stdout), relative_path
      assert_schema(JSON.parse(first.fetch(:stdout)))
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
