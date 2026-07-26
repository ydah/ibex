# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIMessageSentencesTest < Minitest::Test
  def test_errors_list_writes_v2_shortest_sentences_without_creating_a_file
    Dir.mktmpdir("ibex-messages-list") do |directory|
      grammar = File.join(directory, "grammar.y")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")

      listed = capture_cli(["errors", "--list", grammar])

      assert_includes listed, "# ibex-messages v2"
      assert_includes listed, "sentence: $eof"
      assert_includes listed, "sentence: TOKEN TOKEN"
      assert_includes listed, "## E0001"
      refute File.exist?(File.join(directory, "grammar.messages"))
    end
  end

  def test_errors_rejects_conflicting_modes_and_nonpositive_search_limits
    errors = StringIO.new
    status = Ibex::CLI.start(
      ["errors", "--list", "--update", "grammar.y"], stdout: StringIO.new, stderr: errors
    )
    assert_equal 1, status
    assert_match(/accepts only one of --list or --update/, errors.string)

    errors = StringIO.new
    status = Ibex::CLI.start(
      ["errors", "--list", "--max-tokens=0", "grammar.y"], stdout: StringIO.new, stderr: errors
    )
    assert_equal 1, status
    assert_match(/--max-tokens must be positive/, errors.string)
  end

  private

  def capture_cli(arguments)
    output = StringIO.new
    errors = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: output, stderr: errors)
    assert_equal 0, status, errors.string
    output.string
  end
end
