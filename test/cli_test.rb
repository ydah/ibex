# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tempfile"

class CLITest < Minitest::Test
  def test_version
    output = StringIO.new
    assert_equal 0, Ibex::CLI.start(["--version"], stdout: output, stderr: StringIO.new)
    assert_equal "ibex #{Ibex::VERSION}\n", output.string
  end

  def test_emits_grammar_ir
    Tempfile.create(["grammar", ".y"]) do |file|
      file.write("class P\nrule\nstart: TOKEN\nend\n")
      file.flush
      output = StringIO.new
      status = Ibex::CLI.start(["--emit=grammar-ir", file.path], stdout: output, stderr: StringIO.new)
      assert_equal 0, status
      assert_equal "grammar", JSON.parse(output.string).fetch("ibex_ir")
    end
  end

  def test_reports_cli_errors
    errors = StringIO.new
    assert_equal 1, Ibex::CLI.start([], stdout: StringIO.new, stderr: errors)
    assert_equal "(cli):1:1: grammar file is required\n", errors.string
  end
end
