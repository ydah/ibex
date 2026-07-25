# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "json_schemer"
require "stringio"
require "tempfile"
require "tmpdir"

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

  def test_included_fragment_syntax_error_is_one_schema_valid_diagnostic
    include_grammar("fragment\nrule\nhelper: )\nend\n") do |root, fragment|
      result = invoke(["diagnose", "--mode=extended", "--format=json", root])
      diagnostic = assert_resolution_diagnostic(result)

      assert_equal File.realpath(fragment), diagnostic.fetch("location").fetch("file")
      assert_match(/expected a grammar symbol/, diagnostic.fetch("message"))
    end
  end

  def test_missing_include_is_one_schema_valid_diagnostic
    include_grammar(nil) do |root, _fragment|
      result = invoke(["diagnose", "--mode=extended", "--format=json", root])
      diagnostic = assert_resolution_diagnostic(result)

      assert_equal File.realpath(root), diagnostic.fetch("location").fetch("file")
      assert_match(/include file does not exist/, diagnostic.fetch("message"))

      text = invoke(["diagnose", "--mode=extended", root])
      assert_equal 1, text.fetch(:status)
      assert_empty text.fetch(:stderr)
      assert_equal 1, text.fetch(:stdout).lines.length
      assert_match(/root\.y:2:1: include file does not exist/, text.fetch(:stdout))
    end
  end

  def test_unsafe_include_is_one_schema_valid_diagnostic
    Dir.mktmpdir("ibex-diagnostics-security") do |directory|
      root = File.join(directory, "root.y")
      File.write(root, "class P\ninclude \"../escape.y\"\nrule\nstart: TOKEN\nend\n")

      result = invoke(["diagnose", "--mode=extended", "--format=json", root])
      diagnostic = assert_resolution_diagnostic(result)

      assert_equal File.realpath(root), diagnostic.fetch("location").fetch("file")
      assert_match(/parent traversal/, diagnostic.fetch("message"))
    end
  end

  def test_included_fragment_read_error_remains_a_cli_io_error
    include_grammar("fragment\nrule\nhelper: TOKEN\nend\n") do |root, fragment|
      canonical_fragment = File.realpath(fragment)
      binread = File.method(:binread)
      reader = lambda do |path, *arguments|
        raise Errno::EACCES, path if path == canonical_fragment

        binread.call(path, *arguments)
      end

      File.stub(:binread, reader) do
        result = invoke(["diagnose", "--mode=extended", "--format=json", root])
        assert_equal 1, result.fetch(:status)
        assert_empty result.fetch(:stdout)
        assert_match(/Permission denied.*fragment\.y/, result.fetch(:stderr))
      end
    end
  end

  private

  def grammar_file
    Tempfile.create(["diagnostics", ".y"]) do |file|
      file.write(MULTIPLE_ERRORS)
      file.flush
      yield file.path
    end
  end

  def include_grammar(fragment_source)
    Dir.mktmpdir("ibex-diagnostics-include") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      File.write(root, "class P\ninclude \"fragment.y\"\nrule\nstart: helper\nend\n")
      File.write(fragment, fragment_source) if fragment_source
      yield root, fragment
    end
  end

  def assert_resolution_diagnostic(result)
    document = JSON.parse(result.fetch(:stdout))
    assert_equal 1, result.fetch(:status)
    assert_empty result.fetch(:stderr)
    assert SCHEMA.valid?(document), SCHEMA.validate(document).to_a.inspect
    assert_equal false, document.fetch("success")
    assert_equal false, document.fetch("ast_available")
    assert_equal 1, document.fetch("diagnostics").length
    diagnostic = document.fetch("diagnostics").fetch(0)
    assert_equal "frontend.resolution_error", diagnostic.fetch("code")
    diagnostic
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end
end
