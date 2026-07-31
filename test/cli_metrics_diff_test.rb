# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIMetricsDiffTest < Minitest::Test
  def test_analysis_help_does_not_require_inputs
    %w[diff metrics].each do |command|
      output = StringIO.new

      assert_equal 0, Ibex::CLI.start([command, "--help"], stdout: output, stderr: StringIO.new)
      assert_includes output.string, "Usage: ibex #{command}"
    end
  end

  def test_metrics_source_report_matches_public_schema
    with_sources("start: TOKEN", "start: TOKEN") do |before, _after|
      output = StringIO.new

      status = Ibex::CLI.start(["metrics", before], stdout: output, stderr: StringIO.new)
      report = JSON.parse(output.string)

      assert_equal 0, status
      assert_equal "metrics", report.fetch("ibex_report")
      assert_schema("metrics-v1.schema.json", report)
    end
  end

  def test_diff_report_has_all_three_classifications_and_matches_schema
    with_sources("start: A\nold: OLD", "start: B\nnew: NEW") do |before, after|
      output = StringIO.new

      status = Ibex::CLI.start(["diff", before, after], stdout: output, stderr: StringIO.new)
      report = JSON.parse(output.string)

      assert_equal 0, status
      %w[symbols rules conflicts warnings].each do |section|
        assert_equal %w[added changed removed], report.fetch(section).keys.sort
      end
      assert_schema("diff-v1.schema.json", report)
    end
  end

  def test_metrics_accepts_automaton_ir
    Dir.mktmpdir("ibex-metrics") do |directory|
      grammar = normalize("class P\nrule\nstart: TOKEN\nend\n")
      automaton = Ibex::LALR::Builder.new(grammar).build
      path = File.join(directory, "automaton.json")
      File.binwrite(path, Ibex::IR::Serialize.dump(automaton))

      assert_equal 0, Ibex::CLI.start(["metrics", path], stdout: StringIO.new, stderr: StringIO.new)
    end
  end

  private

  def with_sources(before_rules, after_rules)
    Dir.mktmpdir("ibex-analysis") do |directory|
      before = File.join(directory, "before.y")
      after = File.join(directory, "after.y")
      File.binwrite(before, "class Before\nrule\n#{before_rules}\nend\n")
      File.binwrite(after, "class After\nrule\n#{after_rules}\nend\n")
      yield before, after
    end
  end

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "analysis.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def assert_schema(name, report)
    path = File.expand_path("../schema/#{name}", __dir__)
    errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(report).to_a
    assert_empty errors, errors.inspect
  end
end
