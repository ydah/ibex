# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "json_schemer"
require "stringio"
require "tmpdir"

class CLIBisonImportTest < Minitest::Test
  SOURCE = <<~BISON
    %token NUM PLUS
    %unknown setting
    %%
    start: expr ;
    expr: expr PLUS expr { $$ = $1 + $3; }
        | NUM { $$ = $1; }
        ;
    %%
  BISON

  def test_help_does_not_require_an_input
    output = StringIO.new

    assert_equal 0, invoke(["import", "bison", "--help"], output: output)
    assert_includes output.string, "Usage: ibex import bison"
  end

  def test_json_report_matches_schema
    with_source do |path|
      output = StringIO.new

      status = invoke(["import", "bison", "--format=json", path], output: output)
      report = JSON.parse(output.string)

      assert_equal 0, status
      assert_equal "imported_with_unsupported", report.fetch("result")
      assert_equal(["unknown"], report.fetch("unsupported").map { |entry| entry.fetch("name") })
      assert_schema(report)
    end
  end

  def test_source_output_is_atomic_and_rejects_aliases
    Dir.mktmpdir("ibex-bison-output") do |directory|
      input = File.join(directory, "grammar.y")
      output = File.join(directory, "imported.y")
      File.binwrite(input, SOURCE)

      status = invoke(["import", "bison", "-o", output, input], output: StringIO.new)
      assert_equal 0, status
      assert_includes File.binread(output), "class ImportedGrammarParser"

      File.binwrite(output, "sentinel")
      alias_path = File.join(directory, "alias.y")
      File.link(output, alias_path)
      errors = StringIO.new
      status = Ibex::CLI.start(
        ["import", "bison", "-o", output, input], stdout: StringIO.new, stderr: errors
      )
      assert_equal 1, status
      assert_includes errors.string, "multiple hard links"
      assert_equal "sentinel", File.binread(output)

      errors = StringIO.new
      status = Ibex::CLI.start(
        ["import", "bison", "-o", input, input], stdout: StringIO.new, stderr: errors
      )
      assert_equal 1, status
      assert_includes errors.string, "must be distinct"
    end
  end

  def test_budget_exhaustion_returns_two_with_json
    with_source do |path|
      output = StringIO.new

      status = invoke(["import", "bison", "--max-bytes=1", path], output: output)

      assert_equal 2, status
      assert_equal "budget_exhausted", JSON.parse(output.string).fetch("result")
    end
  end

  def test_explain_auto_imports_bison_source
    with_source do |path|
      output = StringIO.new

      status = invoke(
        ["explain", "--format=json", "--counterexample-max-tokens=8", path],
        output: output
      )
      report = JSON.parse(output.string)

      assert_equal 0, status
      refute_empty report.fetch("conflicts")
    end
  end

  def test_generated_import_refuses_ruby_codegen
    with_source do |path|
      imported = StringIO.new
      assert_equal 0, invoke(["import", "bison", path], output: imported)
      imported_path = "#{path}.imported"
      File.binwrite(imported_path, imported.string)
      errors = StringIO.new

      status = Ibex::CLI.start([imported_path], stdout: StringIO.new, stderr: errors)

      assert_equal 1, status
      assert_includes errors.string, "cannot generate Ruby from imported C semantic actions"
    end
  end

  private

  def with_source
    Dir.mktmpdir("ibex-bison") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, SOURCE)
      yield path
    end
  end

  def invoke(arguments, output:)
    Ibex::CLI.start(arguments, stdout: output, stderr: StringIO.new)
  end

  def assert_schema(report)
    path = File.expand_path("../schema/bison-import-v1.schema.json", __dir__)
    errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(report).to_a
    assert_empty errors, errors.inspect
  end
end
