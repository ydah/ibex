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
    locked_path = "/locked/grammar.y"
    binread = File.method(:binread)
    reader = lambda do |path, *arguments|
      raise Errno::EACCES, path if path == locked_path

      binread.call(path, *arguments)
    end

    File.stub(:realpath, locked_path) do
      File.stub(:file?, true) do
        File.stub(:binread, reader) do
          result = invoke([locked_path])
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
