# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLIRailroadTest < Minitest::Test
  def test_writes_railroad_alongside_ruby_output
    with_paths do |grammar, railroad, parser|
      status = run_cli(["--railroad=#{railroad}", "-o", parser, grammar])

      assert_equal 0, status
      assert_includes File.read(railroad), "<svg"
      assert File.exist?(parser)
    end
  end

  def test_writes_identical_railroad_from_source_and_resumed_grammar_ir
    with_paths do |grammar, railroad, _parser|
      grammar_ir = "#{grammar}.json"
      resumed = "#{railroad}.resumed.svg"
      output = StringIO.new

      assert_equal 0, run_cli(["--emit=grammar-ir", "--railroad=#{railroad}", grammar], stdout: output)
      assert_equal "grammar", JSON.parse(output.string).fetch("ibex_ir")
      File.write(grammar_ir, output.string)
      assert_equal 0, run_cli(["--from=grammar-ir", "--emit=sets", "--railroad=#{resumed}", grammar_ir])
      assert_equal File.read(railroad), File.read(resumed)
    end
  end

  def test_writes_railroad_from_resumed_automaton_ir
    with_paths do |grammar, railroad, _parser|
      automaton_ir = "#{grammar}.automaton.json"
      output = StringIO.new

      assert_equal 0, run_cli(["--emit=automaton-ir", grammar], stdout: output)
      File.write(automaton_ir, output.string)
      assert_equal 0, run_cli(["--from=automaton-ir", "--emit=sets", "--railroad=#{railroad}", automaton_ir])
      assert_includes File.read(railroad), "Diagram grammar"
    end
  end

  def test_check_only_does_not_write_railroad
    with_paths do |grammar, railroad, _parser|
      assert_equal 0, run_cli(["--check-only", "--railroad=#{railroad}", grammar])
      refute File.exist?(railroad)
    end
  end

  private

  def with_paths
    Dir.mktmpdir("ibex-railroad") do |directory|
      grammar = File.join(directory, "grammar.y")
      railroad = File.join(directory, "grammar.svg")
      parser = File.join(directory, "parser.rb")
      File.write(grammar, "class Diagram\nrule\nstart: TOKEN | empty\nempty:\nend\n")
      yield grammar, railroad, parser
    end
  end

  def run_cli(arguments, stdout: StringIO.new)
    errors = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: errors)
    assert_equal 0, status, errors.string if status.zero?
    status
  end
end
