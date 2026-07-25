# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLISystemErrorTest < Minitest::Test
  def test_directory_input_is_one_stderr_diagnostic
    Dir.mktmpdir("ibex-read-error") do |directory|
      result = invoke([directory])
      assert_equal 1, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_equal 1, result.fetch(:stderr).lines.length
      assert_includes result.fetch(:stderr), directory
    end
  end

  def test_permission_error_is_one_stderr_diagnostic
    File.stub(:realpath, "/locked/grammar.y") do
      File.stub(:file?, true) do
        File.stub(:binread, ->(*) { raise Errno::EACCES, "/locked/grammar.y" }) do
          result = invoke(["/locked/grammar.y"])
          assert_equal 1, result.fetch(:status)
          assert_empty result.fetch(:stdout)
          assert_equal 1, result.fetch(:stderr).lines.length
          assert_match(/Permission denied.*grammar\.y/, result.fetch(:stderr))
        end
      end
    end
  end

  private

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end
end
