# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"
require "tmpdir"

class ImpactCLIAdversarialTest < Minitest::Test
  def test_unreachable_comparison_uses_state_content_not_numeric_ids
    grammar = normalize_grammar("class P\ntoken TOKEN\nrule\nstart: TOKEN\nend\n")
    base = Ibex::LALR::Builder.new(grammar).build
    before = automaton_with_unreachable(base, [base.states.fetch(0)])
    after = automaton_with_unreachable(base, [base.states.fetch(1), base.states.fetch(0)])
    cli = Ibex::CLI.new(stdout: StringIO.new, stderr: StringIO.new)
    cli.extend(Ibex::CLIImpact)

    assert_equal [base.states.length], cli.send(:newly_unreachable_state_ids, before, after)
  end

  def test_malformed_baseline_is_reported_as_cli_error
    Dir.mktmpdir("ibex-impact-baseline") do |directory|
      before = File.join(directory, "before.y")
      after = File.join(directory, "after.y")
      baseline = File.join(directory, "baseline.json")
      source = "class P\nrule\nstart: TOKEN\nend\n"
      File.binwrite(before, source)
      File.binwrite(after, source)
      File.binwrite(baseline, "[]")
      stdout = StringIO.new
      stderr = StringIO.new

      status = Ibex::CLI.start(["impact", "--baseline=#{baseline}", before, after], stdout: stdout, stderr: stderr)

      assert_equal 1, status
      assert_includes stderr.string, "invalid impact baseline"
    end
  end

  def test_reference_only_change_does_not_crash_or_escalate_seed_to_high
    with_sources(
      "class P\ntoken A\nrule\nstart: left\nleft: A\nright: A\nend\n",
      "class P\ntoken A\nrule\nstart: right\nleft: A\nright: A\nend\n"
    ) do |before, after|
      result = run_impact(["impact", "--severity=info", before, after])
      report = JSON.parse(result.fetch(:stdout))
      start = report.fetch("symbols").find { |symbol| symbol.fetch("symbol") == "start" }

      assert_equal 0, result.fetch(:status)
      assert_equal "medium", start.fetch("severity")
      assert_equal ["reference"], start.fetch("kinds")
    end
  end

  def test_precedence_changes_are_reported_as_medium
    with_sources(
      "class P\ntoken NUM PLUS\npreclow\nleft PLUS\nprechigh\nrule\nstart: expr\nexpr: NUM | expr PLUS expr\nend\n",
      "class P\ntoken NUM PLUS\npreclow\nright PLUS\nprechigh\nrule\nstart: expr\nexpr: NUM | expr PLUS expr\nend\n"
    ) do |before, after|
      result = run_impact(["impact", "--mode=extended", "--severity=medium", before, after])
      report = JSON.parse(result.fetch(:stdout))
      plus = report.fetch("symbols").find { |symbol| symbol.fetch("symbol") == "PLUS" }

      assert_equal 0, result.fetch(:status)
      assert_equal "medium", plus.fetch("severity")
      assert_equal %w[metadata precedence], plus.fetch("kinds")
    end
  end

  private

  def normalize_grammar(source)
    ast = Ibex::Frontend::Parser.new(source, file: "impact-cli.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def automaton_with_unreachable(base, source_states)
    extras = source_states.each_with_index.map do |state, index|
      Ibex::IR::AutomatonState.new(
        id: base.states.length + index, items: state.items, transitions: {}, actions: {}, gotos: {},
        default_action: nil, conflicts: []
      )
    end
    Ibex::IR::Automaton.new(
      grammar: base.grammar, states: base.states + extras, conflict_summary: base.conflict_summary,
      algorithm: base.algorithm, grammar_digest: base.grammar_digest, entry_states: base.entry_states,
      entry_construction: base.entry_construction
    )
  end

  def run_impact(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    { status: Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr), stdout: stdout.string, stderr: stderr.string }
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
