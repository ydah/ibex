# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class CLICommandRegistryTest < Minitest::Test
  COMMANDS = %w[
    check diff impact diagnose coverage config debug doc errors equiv explain fmt fix fuzz test lsp import metrics
    migrate-check migrate-harness reduce samples verify validate-ir compare
  ].freeze

  def test_cli_uses_a_closed_command_registry
    assert_equal COMMANDS, Ibex::CLI::COMMANDS.keys
    assert Ibex::CLI::COMMANDS.values.all?(Ibex::CLI::Command)
  end

  def test_every_subcommand_has_a_fresh_process_help_contract
    COMMANDS.each do |command|
      stdout, stderr, process = Open3.capture3(
        RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", File.expand_path("../exe/ibex", __dir__),
        command, "--help", chdir: File.expand_path("..", __dir__)
      )

      assert process.success?, "#{command}: #{stderr}"
      refute_empty stdout, command
    end
  end
end
