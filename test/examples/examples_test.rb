# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class ExamplesTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EXECUTABLE = File.join(ROOT, "exe/ibex")
  LIBRARY = File.join(ROOT, "lib")

  def test_calculator_example
    output = generate_and_run("calculator", arguments: ["2 + 3 * (4 - 1)"])

    assert_equal "11\n", output
  end

  def test_json_example
    input = '{"name":"Ibex","rocket":"\uD83D\uDE80","values":[1,true,null],"nested":{"x":2.5}}'
    output = generate_and_run("json", input: input)

    assert_equal "{\"name\":\"Ibex\",\"rocket\":\"🚀\",\"values\":[1,true,null],\"nested\":{\"x\":2.5}}\n", output
  end

  def test_ini_example
    input = <<~INI
      title = parser generator
      [server]
      host = localhost
      port = 9292
    INI
    output = generate_and_run("ini", input: input)

    assert_equal(
      "{\"title\":\"parser generator\",\"server\":{\"host\":\"localhost\",\"port\":\"9292\"}}\n",
      output
    )
  end

  def test_tiny_language_example
    input = "answer = 2 + 3 * 4;\nprint answer;\n"
    output = generate_and_run("tiny_language", input: input)

    assert_equal "14\n", output
  end

  private

  def generate_and_run(name, input: "", arguments: [])
    Dir.mktmpdir("ibex-example") do |directory|
      grammar = File.join(ROOT, "examples", "#{name}.y")
      generated = File.join(directory, "#{name}.rb")
      generate_command = [RbConfig.ruby, "-I", LIBRARY, EXECUTABLE, "-o", generated, grammar]
      generation_output, generation_error, generation_status = Open3.capture3(*generate_command, chdir: ROOT)
      assert generation_status.success?, "generation failed:\n#{generation_error}\n#{generation_output}"

      command = [RbConfig.ruby, "-I", LIBRARY, generated, *arguments]
      output, error, status = Open3.capture3(*command, stdin_data: input, chdir: ROOT)
      assert status.success?, "example failed:\n#{error}\n#{output}"
      output
    end
  end
end
