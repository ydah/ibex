# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIIRToolsTest < Minitest::Test
  def test_validate_ir_reports_the_current_document_kind
    output = StringIO.new
    assert_equal 0, run_cli(["validate-ir", fixture_path("grammar.json")], stdout: output)
    assert_equal "valid current grammar IR\n", output.string
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
    output = StringIO.new
    assert_equal 0, run_cli(
      ["compare", fixture_path("grammar.json"), fixture_path("grammar.json")], stdout: output
    )
    result = JSON.parse(output.string)
    assert_equal "grammar", result.fetch("kind")
    assert_empty result.dig("symbols", "added")
    assert_equal 0, result.dig("productions", "count", "delta")
  end

  private

  def run_cli(arguments, stdout: StringIO.new, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
  end

  def fixture_path(name)
    File.expand_path("fixtures/ir/#{name}", __dir__)
  end
end
