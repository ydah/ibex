# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class RaccMigrationTest < Minitest::Test
  def test_compatible_grammar_has_an_empty_success_report
    report = Ibex::RaccMigration::Checker.new.check(
      "class Compat\nrule\nstart: TOKEN\nend\n",
      file: "compat.y"
    )

    assert_predicate report, :compatible?
    assert_equal "Compat", report.class_name
    assert_empty report.findings
    assert_includes report.to_text, "compatible"
    assert_predicate report, :frozen?
  end

  def test_runtime_superclass_and_require_are_reported_without_execution
    source = <<~GRAMMAR
      class Legacy < Racc::Parser
      rule
      start: TOKEN
      end
      ---- inner
      require "racc/parser"
    GRAMMAR

    report = Ibex::RaccMigration::Checker.new.check(source, file: "legacy.y")

    refute_predicate report, :compatible?
    assert_equal %w[racc.runtime_superclass racc.runtime_require], report.findings.map(&:code)
    assert_equal %i[error warning], report.findings.map(&:severity)
  end

  def test_default_mode_syntax_and_normalization_errors_are_structured
    syntax = Ibex::RaccMigration::Checker.new.check(
      "class Extended\nrule\nstart: TOKEN?\nend\n",
      file: "extended.y"
    )
    normalization = Ibex::RaccMigration::Checker.new.check(
      "class Options\noptions mystery\nrule\nstart: TOKEN\nend\n",
      file: "options.y"
    )

    assert_equal ["racc.syntax"], syntax.findings.map(&:code).uniq
    assert_equal ["racc.normalization"], normalization.findings.map(&:code)
    refute_predicate syntax, :compatible?
    refute_predicate normalization, :compatible?
  end

  def test_generated_harness_is_valid_and_runs_both_parsers_in_children
    Dir.mktmpdir("ibex-migration-test-") do |directory|
      grammar = File.join(directory, "grammar.y")
      harness = File.join(directory, "harness.rb")
      generator = File.join(directory, "fake-generator")
      File.write(grammar, "class CompatHarness\nrule\nstart: TOKEN\nend\n")
      File.write(generator, fake_generator_source)
      File.chmod(0o755, generator)

      source = Ibex::RaccMigration::Harness.generate("CompatHarness")
      source = source.sub(
        /CASES = \[\n.*?\n\]\.freeze/m,
        'CASES = [{ name: "value", tokens: [[:TOKEN, 7]] }].freeze'
      )
      File.write(harness, source)

      syntax_output, syntax_error, syntax_status = Open3.capture3(RbConfig.ruby, "-c", harness)
      assert syntax_status.success?, "#{syntax_output}#{syntax_error}"
      output, error, status = Open3.capture3(
        { "RACC" => generator, "IBEX" => generator },
        RbConfig.ruby,
        harness,
        grammar
      )
      assert status.success?, error
      assert_equal "ok value\n", output
    end
  end

  def test_harness_requires_reviewed_cases_before_running_tools
    Dir.mktmpdir("ibex-migration-empty-") do |directory|
      grammar = File.join(directory, "grammar.y")
      harness = File.join(directory, "harness.rb")
      File.write(grammar, "class EmptyHarness\nrule\nstart: TOKEN\nend\n")
      File.write(harness, Ibex::RaccMigration::Harness.generate("EmptyHarness"))

      _output, error, status = Open3.capture3(
        { "RACC" => File.join(directory, "missing"), "IBEX" => File.join(directory, "missing") },
        RbConfig.ruby,
        harness,
        grammar
      )
      refute status.success?
      assert_includes error, "add at least one reviewed entry to CASES"
    end
  end

  private

  def fake_generator_source
    <<~RUBY
      #!/usr/bin/env ruby
      output = ARGV.fetch(ARGV.index("-o") + 1)
      File.write(output, <<~'PARSER')
        class CompatHarness
          def do_parse
            token = next_token
            token && token.fetch(1)
          end
        end
      PARSER
    RUBY
  end
end
