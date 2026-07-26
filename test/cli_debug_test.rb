# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"
require "stringio"

class CLIDebugTest < Minitest::Test
  AUTOMATON = File.expand_path("fixtures/ir/automaton-v2.json", __dir__)
  GRAMMAR = File.expand_path("fixtures/ir/grammar-v2.json", __dir__)
  SCHEMA = JSONSchemer.schema(
    JSON.parse(File.read(File.expand_path("../schema/table-simulation-v1.schema.json", __dir__)))
  )

  def test_json_simulation_is_schema_valid_and_deterministic
    arguments = ["debug", AUTOMATON, "NUMBER", "PLUS", "NUMBER", "--format=json"]
    first = StringIO.new
    second = StringIO.new

    assert_equal 0, run_cli(arguments, stdout: first)
    assert_equal 0, run_cli(arguments, stdout: second)
    assert_equal first.string, second.string
    document = JSON.parse(first.string)
    assert_empty SCHEMA.validate(document).to_a
    assert_equal "accepted", document.fetch("status")
    assert_equal %w[NUMBER PLUS NUMBER], document.fetch("tokens")
  end

  def test_text_simulation_reports_an_implicit_error_with_nonzero_status
    output = StringIO.new
    assert_equal 1, run_cli(["debug", AUTOMATON, "PLUS"], stdout: output)

    assert_includes output.string, "state=0 token=\"PLUS\" action=error source=implicit"
    assert output.string.end_with?("status=error\n")
  end

  def test_stdin_mode_processes_tokens_once_and_finishes_on_blank_line
    input = StringIO.new("NUMBER\nPLUS\nNUMBER\n\n")
    output = StringIO.new

    assert_equal 0, run_cli(["debug", AUTOMATON], stdin: input, stdout: output)
    action_lines = output.string.lines.count { |line| line.match?(/\A\d+:/) }
    status_lines = output.string.lines.count { |line| line == "status=accepted\n" }
    assert_equal 7, action_lines
    assert_equal 1, status_lines
  end

  def test_rejects_grammar_ir_unknown_tokens_and_invalid_budgets
    cases = [
      ["debug"],
      ["debug", GRAMMAR, "NUMBER"],
      ["debug", AUTOMATON, "MISSING"],
      ["debug", AUTOMATON, "NUMBER", "--max-steps=1"],
      ["debug", AUTOMATON, "NUMBER", "--max-stack=0"]
    ]

    cases.each do |arguments|
      errors = StringIO.new
      assert_equal 1, run_cli(arguments, stderr: errors), arguments.inspect
      refute_empty errors.string
    end
  end

  private

  def run_cli(arguments, stdin: StringIO.new, stdout: StringIO.new, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdin: stdin, stdout: stdout, stderr: stderr)
  end
end
