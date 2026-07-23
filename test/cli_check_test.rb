# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLICheckTest < Minitest::Test
  def test_verifies_generated_parser_without_rewriting_it
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")

      assert_equal 0, run_cli(["-o", parser, grammar])
      assert_equal 0, run_cli(["--check", "-o", parser, grammar])

      File.write(parser, "# stale\n")
      errors = StringIO.new
      assert_equal 1, run_cli(["--check", "-o", parser, grammar], stderr: errors)
      assert_match(/generated parser is stale/, errors.string)
      assert_equal "# stale\n", File.read(parser)
    end
  end

  def test_reports_a_missing_generated_parser
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "missing.rb")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      errors = StringIO.new

      assert_equal 1, run_cli(["--check", "-o", parser, grammar], stderr: errors)
      assert_match(/generated parser is missing/, errors.string)
      refute File.exist?(parser)
    end
  end

  def test_check_is_side_effect_free_for_reports_and_visualizations
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      report = File.join(directory, "parser.output")
      dot = File.join(directory, "parser.dot")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      assert_equal 0, run_cli(["-o", parser, grammar])

      assert_equal 0, run_cli(["--check", "-v", "-O", report, "--dot", dot, "--railroad", parser,
                               "-o", parser, grammar])
      refute File.exist?(report)
      refute File.exist?(dot)
      assert File.read(parser).start_with?("# frozen_string_literal:")
    end
  end

  def test_check_rejects_options_that_bypass_ruby_generation
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "parser.y")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")

      errors = StringIO.new
      assert_equal 1, run_cli(["--check", "--emit=sets", grammar], stderr: errors)
      assert_match(/--check requires --emit=ruby/, errors.string)

      errors = StringIO.new
      assert_equal 1, run_cli(["--check", "--check-only", grammar], stderr: errors)
      assert_match(/cannot be combined/, errors.string)
    end
  end

  def test_check_verifies_requested_rbs_output
    Dir.mktmpdir do |directory|
      grammar = File.join(directory, "parser.y")
      parser = File.join(directory, "parser.rb")
      signature = File.join(directory, "parser.rbs")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")
      assert_equal 0, run_cli(["--rbs", "-o", parser, grammar])
      assert_equal 0, run_cli(["--check", "--rbs", "-o", parser, grammar])

      File.write(signature, "class Stale\nend\n")
      errors = StringIO.new
      assert_equal 1, run_cli(["--check", "--rbs", "-o", parser, grammar], stderr: errors)
      assert_match(/generated RBS signature is stale/, errors.string)
    end
  end

  private

  def run_cli(arguments, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: StringIO.new, stderr: stderr)
  end
end
