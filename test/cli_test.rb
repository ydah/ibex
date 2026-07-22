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

  def test_emits_automaton_ir
    Tempfile.create(["grammar", ".y"]) do |file|
      file.write("class P\nrule\nstart: TOKEN\nend\n")
      file.flush
      output = StringIO.new
      status = Ibex::CLI.start(["--emit=automaton-ir", file.path], stdout: output, stderr: StringIO.new)
      assert_equal 0, status
      assert_equal "automaton", JSON.parse(output.string).fetch("ibex_ir")
    end
  end

  def test_generates_ruby_file
    Tempfile.create(["grammar", ".y"]) do |grammar|
      Tempfile.create(["parser", ".rb"]) do |output|
        grammar.write("class P\nrule\nstart: TOKEN\nend\n")
        grammar.flush
        status = Ibex::CLI.start(["--table=plain", "-o", output.path, grammar.path],
                                 stdout: StringIO.new, stderr: StringIO.new)
        assert_equal 0, status
        assert_includes File.read(output.path), "class P < Ibex::Runtime::Parser"
      end
    end
  end

  def test_ast_and_check_only_status_options
    with_grammar do |grammar|
      ast_output = StringIO.new
      assert_equal 0, Ibex::CLI.start(["--emit=ast", grammar.path], stdout: ast_output, stderr: StringIO.new)
      assert_equal "Root", JSON.parse(ast_output.string).fetch("node")

      status_output = StringIO.new
      assert_equal 0, Ibex::CLI.start(["-C", "-S", grammar.path], stdout: StringIO.new, stderr: status_output)
      assert_includes status_output.string, "reading"
    end
  end

  def test_report_executable_and_superclass_options
    with_grammar do |grammar|
      Tempfile.create(["report", ".output"]) do |report|
        Tempfile.create(["parser", ".rb"]) do |output|
          arguments = ["-v", "-O", report.path, "-e", "/usr/bin/env ruby", "--superclass=Ibex::Runtime::Parser",
                       "-o", output.path, grammar.path]
          assert_equal 0, Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: StringIO.new)
          assert_includes File.read(report.path), "State 0"
          assert File.executable?(output.path)
          assert File.read(output.path).start_with?("#!/usr/bin/env ruby\n")
        end
      end
    end
  end

  def test_help_lists_compatible_options
    output = StringIO.new
    assert_equal 0, Ibex::CLI.start(["--help"], stdout: output, stderr: StringIO.new)
    %w[--output-file --debug --verbose --embedded --check-only --superclass].each do |option|
      assert_includes output.string, option
    end
  end

  def test_reports_cli_errors
    errors = StringIO.new
    assert_equal 1, Ibex::CLI.start([], stdout: StringIO.new, stderr: errors)
    assert_equal "(cli):1:1: grammar file is required\n", errors.string
  end

  private

  def with_grammar
    Tempfile.create(["grammar", ".y"]) do |grammar|
      grammar.write("class P\nrule\nstart: TOKEN\nend\n")
      grammar.flush
      yield grammar
    end
  end
end
