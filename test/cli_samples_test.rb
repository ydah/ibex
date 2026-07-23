# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLISamplesTest < Minitest::Test
  def test_generates_deterministic_json_lines
    with_grammar do |grammar|
      first = StringIO.new
      second = StringIO.new
      arguments = [
        "samples", "--count=6", "--seed=12", "--max-tokens=7", "--max-expansions=1000", grammar
      ]

      assert_equal 0, run_cli(arguments, stdout: first)
      assert_equal 0, run_cli(arguments, stdout: second)
      assert_equal first.string, second.string
      samples = first.string.lines.map { |line| JSON.parse(line) }
      assert_equal 6, samples.length
      assert(samples.all? { |sample| sample.length <= 7 })
    end
  end

  def test_resumes_from_grammar_ir
    with_grammar do |grammar|
      json = StringIO.new
      assert_equal 0, run_cli(["--emit=grammar-ir", grammar], stdout: json)
      ir_path = "#{grammar}.json"
      File.write(ir_path, json.string)
      output = StringIO.new

      assert_equal 0, run_cli(["samples", "--from=grammar-ir", "--count=1", ir_path], stdout: output)
      assert_kind_of Array, JSON.parse(output.string)
    end
  end

  def test_rejects_nonpositive_bounds
    with_grammar do |grammar|
      %w[--count=0 --max-expansions=0].each do |argument|
        errors = StringIO.new
        assert_equal 1, run_cli(["samples", argument, grammar], stderr: errors)
        assert_match(/invalid argument: #{Regexp.escape(argument)}/, errors.string)
      end
    end
  end

  private

  def with_grammar
    Dir.mktmpdir do |directory|
      path = File.join(directory, "list.y")
      File.write(path, "class List\nrule\nstart: ITEM | ITEM ',' start\nend\n")
      yield path
    end
  end

  def run_cli(arguments, stdout: StringIO.new, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
  end
end
