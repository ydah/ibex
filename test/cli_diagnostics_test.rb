# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "json_schemer"
require "stringio"
require "tempfile"

class CLIDiagnosticsTest < Minitest::Test
  MULTIPLE_ERRORS = <<~GRAMMAR
    class P
    expect nope
    token GOOD
    rule
    broken: A | ) | B
    later: GOOD
    end
  GRAMMAR
  private_constant :MULTIPLE_ERRORS

  SCHEMA = JSONSchemer.schema(
    JSON.parse(File.read(File.expand_path("../schema/frontend-diagnostics-v1.schema.json", __dir__)))
  )

  def test_text_diagnostics_are_explicit_and_positioned
    grammar_file do |path|
      result = invoke(["diagnose", path])

      assert_equal 1, result.fetch(:status)
      assert_empty result.fetch(:stderr)
      lines = result.fetch(:stdout).lines
      assert_equal 2, lines.length
      assert_match(/:2:8: expected integer, got nope/, lines.first)
      assert_match(/:5:13: expected a grammar symbol, got \)/, lines.last)
    end
  end

  def test_json_is_versioned_schema_valid_and_reports_partial_ast
    grammar_file do |path|
      result = invoke(["diagnose", "--format=json", path])
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 1, result.fetch(:status)
      assert SCHEMA.valid?(document), SCHEMA.validate(document).to_a.inspect
      assert_equal "frontend", document.fetch("ibex_diagnostics")
      assert_equal 1, document.fetch("schema_version")
      assert_equal false, document.fetch("success")
      assert_equal true, document.fetch("ast_available")
      codes = document.fetch("diagnostics").map { |diagnostic| diagnostic.fetch("code") }
      assert_equal %w[frontend.syntax_error frontend.syntax_error], codes
    end
  end

  def test_success_and_max_validation
    Tempfile.create(["valid", ".y"]) do |file|
      file.write("class P\nrule\nstart: TOKEN\nend\n")
      file.flush
      result = invoke(["diagnose", "--format=json", file.path])
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 0, result.fetch(:status)
      assert_equal true, document.fetch("success")
      assert_empty document.fetch("diagnostics")
    end

    %w[0 -1 nope].each do |value|
      result = invoke(["diagnose", "--max-diagnostics=#{value}", "grammar.y"])
      assert_equal 1, result.fetch(:status)
      assert_match(/invalid argument: --max-diagnostics/, result.fetch(:stderr))
    end
  end

  def test_limit_and_help_are_deterministic
    grammar_file do |path|
      result = invoke(["diagnose", "--format=json", "--max-diagnostics=1", path])
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 1, result.fetch(:status)
      assert_equal 1, document.fetch("diagnostics").length
      assert_equal false, document.fetch("ast_available")
    end

    help = invoke(%w[diagnose --help])
    assert_equal 0, help.fetch(:status)
    assert_match(/Usage: ibex diagnose/, help.fetch(:stdout))
  end

  private

  def grammar_file
    Tempfile.create(["diagnostics", ".y"]) do |file|
      file.write(MULTIPLE_ERRORS)
      file.flush
      yield file.path
    end
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end
end
