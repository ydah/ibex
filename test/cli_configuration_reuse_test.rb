# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIConfigurationReuseTest < Minitest::Test
  MODE_SUBCOMMANDS = %w[doc diagnose fmt].freeze
  ALGORITHM_SUBCOMMANDS = %w[metrics equiv fix].freeze
  FIX_SOURCE = <<~GRAMMAR
    class ReuseFixParser
    pragma extended
    expect 1
    rule
    start: expr
    expr: expr PLUS expr | NUM
    end
  GRAMMAR

  def test_command_local_modes_do_not_leak_after_success
    with_extended_include do |root|
      MODE_SUBCOMMANDS.each do |command|
        cli, stdout, stderr = reusable_cli
        status = cli.run([command, "--mode=extended", root])
        assert_equal 0, status, "#{command}: #{stderr.string}"

        reset_streams(stdout, stderr)
        assert_default_mode_rejects_include(cli, root, stderr, command)
      end
    end
  end

  def test_command_local_modes_do_not_leak_through_parse_failure
    with_extended_include do |root|
      MODE_SUBCOMMANDS.each do |command|
        cli, stdout, stderr = reusable_cli
        assert_equal 1, cli.run([command, "--mode=extended", "--unknown-option", root]), command

        reset_streams(stdout, stderr)
        assert_default_mode_rejects_include(cli, root, stderr, command)
      end
    end
  end

  def test_command_local_analysis_algorithms_do_not_leak_after_success
    with_algorithm_grammars do |path, fix_path|
      ALGORITHM_SUBCOMMANDS.each do |command|
        cli, stdout, stderr = reusable_cli
        command_path = command == "fix" ? fix_path : path
        status = cli.run(algorithm_command(command, command_path))
        assert_equal 0, status, "#{command}: #{stderr.string}"

        reset_streams(stdout, stderr)
        assert_default_generation_algorithm(cli, command_path, stdout, stderr, command)
      end
    end
  end

  def test_command_local_analysis_algorithms_do_not_leak_through_parse_failure
    with_grammar do |path|
      ALGORITHM_SUBCOMMANDS.each do |command|
        cli, stdout, stderr = reusable_cli
        arguments = algorithm_command(command, path)
        arguments.insert(2, "--unknown-option")
        assert_equal 1, cli.run(arguments), command

        reset_streams(stdout, stderr)
        assert_default_generation_algorithm(cli, path, stdout, stderr, command)
      end
    end
  end

  private

  def reusable_cli
    stdout = StringIO.new
    stderr = StringIO.new
    [Ibex::CLI.new(stdout: stdout, stderr: stderr), stdout, stderr]
  end

  def reset_streams(*streams)
    streams.each do |stream|
      stream.truncate(0)
      stream.rewind
    end
  end

  def assert_default_mode_rejects_include(cli, root, stderr, command)
    assert_equal 1, cli.run(["--emit=grammar-ir", root]), command
    assert_match(/includes require extended mode/, stderr.string, command)
  end

  def assert_default_generation_algorithm(cli, path, stdout, stderr, command)
    assert_equal 0, cli.run(["--emit=automaton-ir", path]), "#{command}: #{stderr.string}"
    assert_equal "lalr1", JSON.parse(stdout.string).fetch("algorithm"), command
  end

  def algorithm_command(command, path)
    case command
    when "metrics" then [command, "--algorithm=lr1", path]
    when "equiv" then [command, "--algorithm=lr1", path, path]
    when "fix"
      [
        command, "--algorithm=lr1", "--mode=extended", "--equiv-samples=10",
        "--equiv-max-tokens=6", "--equiv-max-configurations=1000", path
      ]
    else raise "unknown test command: #{command}"
    end
  end

  def with_algorithm_grammars
    Dir.mktmpdir("ibex-configuration-reuse") do |directory|
      path = File.join(directory, "grammar.y")
      fix_path = File.join(directory, "fix.y")
      File.binwrite(path, "class ReuseParser\nrule\nstart: TOKEN\nend\n")
      File.binwrite(fix_path, FIX_SOURCE)
      yield path, fix_path
    end
  end

  def with_grammar
    Dir.mktmpdir("ibex-configuration-reuse") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, "class ReuseParser\nrule\nstart: TOKEN\nend\n")
      yield path
    end
  end

  def with_extended_include
    Dir.mktmpdir("ibex-mode-reuse") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      File.binwrite(root, "class ReuseParser\ninclude \"fragment.y\"\nrule\nstart: helper\nend\n")
      File.binwrite(fragment, "fragment\nrule\nhelper: TOKEN\nend\n")
      yield root
    end
  end
end
