# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class ReadmeTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_calculator_quickstart_runs_as_documented
    readme = File.read(File.join(ROOT, "README.md"))
    grammar = readme.match(/<!-- calculator-grammar:start -->\n```text\n(.*?)```\n<!-- calculator-grammar:end -->/m)
    refute_nil grammar, "README calculator grammar marker is missing"

    Dir.mktmpdir("ibex-readme") do |directory|
      grammar_path = File.join(directory, "calculator.y")
      File.write(grammar_path, grammar[1])
      _output, errors, status = Open3.capture3(RbConfig.ruby, "-Ilib", "exe/ibex", grammar_path, chdir: ROOT)
      assert status.success?, errors

      parser_path = File.join(directory, "calculator.rb")
      output, errors, status = Open3.capture3(RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", parser_path)
      assert status.success?, errors
      assert_equal "14\n", output
    end
  end
end
