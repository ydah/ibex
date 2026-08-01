# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIFixTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class Parser
    pragma extended
    expect 1

    rule
      start: expr
      expr: expr PLUS expr
          | NUM
    end
  GRAMMAR

  def test_fix_help_does_not_require_an_input
    output = StringIO.new

    assert_equal 0, Ibex::CLI.start(%w[fix --help], stdout: output, stderr: StringIO.new)
    assert_includes output.string, "Usage: ibex fix"
  end

  def test_fix_reports_safe_proposals_and_matches_schema
    with_grammar do |path|
      output = StringIO.new

      status = invoke(["fix", *bounded_options, path], output: output)
      report = JSON.parse(output.string)

      assert_equal 0, status
      assert_equal "proposals_found", report.fetch("result")
      assert_equal 4, report.fetch("candidate_space").length
      advice_categories = report.fetch("advice").map { |entry| entry.fetch("category") }
      assert_equal %w[expectation_declaration recovery_quality], advice_categories
      unsafe = report.fetch("proposals").reject do |proposal|
        proposal.dig("equivalence", "result") == "no_difference_within_bounds"
      end
      assert_empty unsafe
      assert_schema(report)
    end
  end

  def test_fix_apply_uses_transactional_source_replacement
    with_grammar do |path|
      output = StringIO.new

      status = invoke(["fix", "--apply", *bounded_options, path], output: output)
      report = JSON.parse(output.string)
      grammar, automaton = build(File.binread(path), path)

      assert_equal 0, status
      assert_match(/\AFX\d{3}\z/, report.fetch("applied"))
      assert_equal 0, automaton.conflict_summary.fetch(:sr)
      assert_equal 0, grammar.expect
      assert_includes File.binread(path), "right PLUS"
      assert_schema(report)
    end
  end

  def test_fix_apply_rejects_multiple_hard_links
    Dir.mktmpdir("ibex-fix-hardlink") do |directory|
      path = File.join(directory, "grammar.y")
      alias_path = File.join(directory, "grammar-alias.y")
      File.binwrite(path, SOURCE)
      File.link(path, alias_path)
      errors = StringIO.new

      status = Ibex::CLI.start(
        ["fix", "--apply", *bounded_options, path],
        stdout: StringIO.new, stderr: errors
      )

      assert_equal 1, status
      assert_includes errors.string, "multiple hard links"
      assert_equal SOURCE, File.binread(path)
    end
  end

  def test_fix_apply_rejects_a_symlink_input
    Dir.mktmpdir("ibex-fix-symlink") do |directory|
      target = File.join(directory, "grammar.y")
      path = File.join(directory, "grammar-link.y")
      File.binwrite(target, SOURCE)
      File.symlink(target, path)
      errors = StringIO.new

      status = Ibex::CLI.start(
        ["fix", "--apply", *bounded_options, path],
        stdout: StringIO.new, stderr: errors
      )

      assert_equal 1, status
      assert_includes errors.string, "symlink aliases"
      assert_equal SOURCE, File.binread(target)
    end
  end

  def test_fix_returns_two_for_candidate_budget_exhaustion
    with_grammar do |path|
      output = StringIO.new

      status = invoke(["fix", "--max-candidates=1", path], output: output)

      assert_equal 2, status
      assert_equal "budget_exhausted", JSON.parse(output.string).fetch("result")
    end
  end

  def test_fix_returns_two_for_independent_verifier_budget_exhaustion
    with_grammar do |path|
      output = StringIO.new

      status = invoke(
        ["fix", "--verify-max-items=1", *bounded_options, path],
        output: output
      )
      report = JSON.parse(output.string)

      assert_equal 2, status
      assert_equal "budget_exhausted", report.fetch("result")
      assert_equal "candidate_evaluation", report.fetch("phase")
      assert_includes report.fetch("rejections").map { |entry| entry.fetch("reason") },
                      "verification_budget_exhausted"
      assert_schema(report)
    end
  end

  def test_fix_reports_configured_message_catalog_effects
    with_grammar do |path|
      _grammar, automaton = build(File.binread(path), path)
      message_path = "#{path}.messages"
      File.binwrite(message_path, Ibex::ErrorMessages.render(automaton))
      output = StringIO.new

      status = invoke(["fix", "--messages=#{message_path}", *bounded_options, path], output: output)
      impact = JSON.parse(output.string).fetch("proposals").fetch(0)
                   .dig("side_effects", "message_catalog")

      assert_equal 0, status
      assert_equal "evaluated", impact.fetch("status")
      assert_equal message_path, impact.fetch("file")
    end
  end

  def test_fix_refuses_structurally_incomplete_bison_source
    with_grammar do |path|
      File.binwrite(path, "%unknown setting\n%%\nstart: ITEM;\n%%\n")
      errors = StringIO.new

      status = Ibex::CLI.start(
        ["fix", path], stdout: StringIO.new, stderr: errors
      )

      assert_equal 1, status
      assert_includes errors.string, "structurally incomplete"
      assert_includes errors.string, "unknown"
    end
  end

  private

  def bounded_options
    %w[--mode=extended --equiv-samples=10 --equiv-max-tokens=6 --equiv-max-configurations=1000]
  end

  def with_grammar
    Dir.mktmpdir("ibex-fix") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, SOURCE)
      yield path
    end
  end

  def invoke(arguments, output:)
    Ibex::CLI.start(arguments, stdout: output, stderr: StringIO.new)
  end

  def build(source, path)
    ast = Ibex::Frontend::Parser.new(source, file: path, mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    [grammar, Ibex::LALR::Builder.new(grammar).build]
  end

  def assert_schema(report)
    path = File.expand_path("../schema/fix-v3.schema.json", __dir__)
    errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(report).to_a
    assert_empty errors, errors.inspect
  end
end
