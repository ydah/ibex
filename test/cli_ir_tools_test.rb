# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIIRToolsTest < Minitest::Test
  def test_validate_ir_reports_the_document_kind
    with_grammar_irs do |before, _after|
      output = StringIO.new
      assert_equal 0, run_cli(["validate-ir", before], stdout: output)
      assert_equal "valid grammar IR v1\n", output.string
    end
  end

  def test_validate_ir_normalizes_invalid_input_to_a_positioned_error
    Dir.mktmpdir do |directory|
      path = File.join(directory, "broken.json")
      File.write(path, '{"ibex_ir":"grammar","schema_version":1}')
      errors = StringIO.new

      assert_equal 1, run_cli(["validate-ir", path], stderr: errors)
      assert_match(/\(ir\):1:1:/, errors.string)
    end
  end

  def test_compare_reports_deterministic_structural_changes
    with_grammar_irs do |before, after|
      output = StringIO.new
      assert_equal 0, run_cli(["compare", before, after], stdout: output)
      result = JSON.parse(output.string)
      assert_equal "grammar", result.fetch("kind")
      assert_equal ["EXTRA"], result.dig("symbols", "added")
      assert_equal 1, result.dig("productions", "count", "delta")
    end
  end

  private

  def with_grammar_irs
    Dir.mktmpdir do |directory|
      before = grammar_ir("class P\nrule\nstart: ITEM\nend\n")
      after = grammar_ir("class P\ntoken EXTRA\nrule\nstart: ITEM | EXTRA\nend\n")
      before_path = File.join(directory, "before.json")
      after_path = File.join(directory, "after.json")
      File.write(before_path, Ibex::IR::Serialize.dump(before))
      File.write(after_path, Ibex::IR::Serialize.dump(after))
      yield before_path, after_path
    end
  end

  def grammar_ir(source)
    ast = Ibex::Frontend::Parser.new(source, file: "compare.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def run_cli(arguments, stdout: StringIO.new, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
  end
end
