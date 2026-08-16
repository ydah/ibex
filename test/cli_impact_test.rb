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

  def test_schema_rejects_unknown_conflict_record_keys
    with_grammars("start: TOKEN", "start: TOKEN") do |before, after|
      report = JSON.parse(run_impact(["impact", before, after]).fetch(:stdout))
      report.fetch("automaton").fetch("conflicts").fetch("added") << { "unexpected" => true }

      schema = JSON.parse(File.binread(File.expand_path("../schema/impact-v1.schema.json", __dir__)))
      errors = JSONSchemer.schema(schema).validate(report).to_a
      refute_empty errors
    end
  end

  def test_removed_nonterminal_is_reported_and_gated
    with_grammars("start: TOKEN\nold: TOKEN", "start: TOKEN") do |before, after|
      result = run_impact(["impact", "--fail-on=first_change", before, after])
      report = JSON.parse(result.fetch(:stdout))

      assert_equal 1, result.fetch(:status)
      assert_includes report.fetch("seeds").map { |seed| seed.fetch("symbol") }, "old"
      old = report.fetch("symbols").find { |symbol| symbol.fetch("symbol") == "old" }
      assert_equal "high", old.fetch("severity")
      assert_includes old.fetch("kinds"), "first"
    end
  end

  def test_metadata_changes_are_reported_as_low
    with_sources(
      "class P\npragma extended\ntoken X\ndisplay X \"old\"\nrule\nstart: X\nend\n",
      "class P\npragma extended\ntoken X\ndisplay X \"new\"\nrule\nstart: X\nend\n"
    ) do |before, after|
      report = JSON.parse(run_impact(["impact", "--mode=extended", "--severity=low", before, after]).fetch(:stdout))
      symbol = report.fetch("symbols").find { |entry| entry.fetch("symbol") == "X" }

      assert_equal "low", symbol.fetch("severity")
      assert_equal ["metadata"], symbol.fetch("kinds")
    end
  end

  def test_severity_threshold_filters_actions
    with_sources(
      "class P\ntoken A B\nrule\nstart: A { result = val[0] }\nend\n",
      "class P\ntoken A B\nrule\nstart: A B { result = val[0] }\nend\n"
    ) do |before, after|
      report = JSON.parse(run_impact(["impact", "--severity=critical", before, after]).fetch(:stdout))

      assert_empty report.fetch("actions")
    end
  end

  def test_symbols_are_sorted_by_name
    with_sources(
      "class P\nrule\nstart: zeta alpha\nzeta: Z\nalpha: A\nend\n",
      "class P\nrule\nstart: zeta alpha\nzeta: Z\nalpha: A\nend\n"
    ) do |before, _after|
      report = JSON.parse(run_impact(["impact", "--symbol=zeta,alpha", "--severity=info", before]).fetch(:stdout))

      symbols = report.fetch("symbols").map { |entry| entry.fetch("symbol") }
      assert_equal %w[alpha start zeta], symbols
    end
  end

  def test_baseline_filter_updates_critical_totals
    with_grammars(
      "statement: ID",
      "statement: IF expression THEN statement | IF expression THEN statement ELSE statement | ID\nexpression: ID"
    ) do |before, after|
      Dir.mktmpdir("ibex-impact-baseline") do |directory|
        baseline = File.join(directory, "baseline.json")
        run_impact(["impact", "--baseline=#{baseline}", "--update-baseline", before, after])
        report = JSON.parse(run_impact(["impact", "--baseline=#{baseline}", before, after]).fetch(:stdout))

        assert_empty report.dig("automaton", "conflicts", "added")
        assert_equal 0, report.dig("totals", "critical")
      end
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

  def with_sources(before_source, after_source)
    Dir.mktmpdir("ibex-impact") do |directory|
      before = File.join(directory, "before.y")
      after = File.join(directory, "after.y")
      File.binwrite(before, before_source)
      File.binwrite(after, after_source)
      yield before, after
    end
  end
end
