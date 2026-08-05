# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIConfigModeProvenanceTest < Minitest::Test
  def test_explicit_extended_mode_is_reported_as_cli_only
    with_grammar("class P\nrule\nstart: TOKEN\nend\n") do |path|
      result = invoke(["config", "--mode=extended", "--format=json", path])
      mode = configuration(JSON.parse(result.fetch(:stdout)), "grammar.mode")
      sources = mode.fetch("evidence").map { |entry| entry.fetch("source") }

      assert_equal 0, result.fetch(:status)
      assert_equal "extended", mode.fetch("value")
      assert_equal "cli", mode.dig("origin", "kind")
      assert_equal ["cli"], sources
      assert_empty result.fetch(:stderr)
    end
  end

  def test_extended_pragma_conflict_uses_the_pragma_location
    source = "class P\n\npragma extended\nrule\nstart: TOKEN\nend\n"
    with_grammar(source) do |path|
      result = invoke(["config", "--mode=default", "--format=json", path])
      document = JSON.parse(result.fetch(:stdout))
      mode = configuration(document, "grammar.mode")
      expected_location = {
        "file" => File.realpath(path), "line" => 3, "column" => 1, "end_line" => 3, "end_column" => 1
      }

      assert_equal 1, result.fetch(:status)
      assert_equal "conflict", document.fetch("status")
      assert_equal expected_location, mode.dig("origin", "location")
      assert_equal expected_location, mode.fetch("evidence").first.fetch("location")
      assert_match(/#{Regexp.escape(File.realpath(path))}:3:1: configuration conflict/, result.fetch(:stderr))
    end
  end

  private

  def configuration(document, key)
    document.fetch("configuration").find { |entry| entry.fetch("key") == key } || flunk("missing #{key}")
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end

  def with_grammar(source)
    Dir.mktmpdir("ibex-config") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      yield path
    end
  end
end
