# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class CLILoadingTest < Minitest::Test
  UNRELATED_GENERATION_FEATURES = %w[
    ibex/cli/coverage.rb
    ibex/cli/lsp.rb
    ibex/cli/racc_migration.rb
    ibex/coverage.rb
    ibex/grammar_tests.rb
    ibex/lsp.rb
    ibex/racc_migration.rb
    ibex/samples.rb
    ibex/table_simulation.rb
  ].freeze
  LOADED_FEATURES_SCRIPT = <<~'RUBY'
    require "json"
    require "stringio"
    require "ibex/cli"

    status =
      case ARGV.first
      when nil
        nil
      when "lsp"
        Ibex::CLI.start(%w[lsp --help], stdout: StringIO.new, stderr: StringIO.new)
      when "explain"
        Ibex::CLI.start(["explain", "--format=json", ARGV.fetch(1)],
                        stdout: StringIO.new, stderr: StringIO.new)
      else
        Ibex::CLI.start(["-o", ARGV.fetch(1), ARGV.fetch(0)],
                        stdout: StringIO.new, stderr: StringIO.new)
      end
    library = File.expand_path("lib", Dir.pwd)
    features = $LOADED_FEATURES.filter_map do |path|
      expanded = File.expand_path(path)
      expanded.delete_prefix("#{library}/") if expanded.start_with?("#{library}/ibex")
    end
    puts JSON.generate(
      status: status,
      features: features.sort,
      constants: {
        CLILSP: Ibex.const_defined?(:CLILSP, false),
        CLICoverage: Ibex.const_defined?(:CLICoverage, false)
      }
    )
  RUBY

  def test_requiring_cli_registers_but_does_not_load_optional_subcommands
    result = loaded_features_after

    assert_includes result.fetch("features"), "ibex/cli.rb"
    assert_equal true, result.fetch("constants").fetch("CLILSP")
    assert_equal true, result.fetch("constants").fetch("CLICoverage")
    assert_empty result.fetch("features") & UNRELATED_GENERATION_FEATURES
  end

  def test_ordinary_generation_does_not_load_unrelated_subsystems
    Dir.mktmpdir("ibex-cli-loading") do |directory|
      grammar = File.join(directory, "grammar.y")
      output = File.join(directory, "parser.rb")
      File.write(grammar, "class P\nrule\nstart: TOKEN\nend\n")

      result = loaded_features_after(grammar, output)

      assert_equal 0, result.fetch("status")
      assert File.file?(output)
      assert_includes result.fetch("features"), "ibex/codegen/ruby.rb"
      assert_empty result.fetch("features") & UNRELATED_GENERATION_FEATURES
    end
  end

  def test_subcommand_dispatch_loads_only_the_selected_subsystem
    result = loaded_features_after("lsp")

    assert_equal 0, result.fetch("status")
    assert_includes result.fetch("features"), "ibex/cli/lsp.rb"
    assert_includes result.fetch("features"), "ibex/lsp.rb"
    refute_includes result.fetch("features"), "ibex/coverage.rb"
    refute_includes result.fetch("features"), "ibex/racc_migration.rb"
  end

  def test_selected_subcommand_declares_its_transitive_dependencies
    grammar = File.expand_path("../benchmark/grammars/representative.y", __dir__)
    result = loaded_features_after("explain", grammar)

    assert_equal 0, result.fetch("status")
    assert_includes result.fetch("features"), "ibex/cli/explain.rb"
    assert_includes result.fetch("features"), "ibex/codegen/explain.rb"
    assert_includes result.fetch("features"), "ibex/codegen/symbol_labels.rb"
    refute_includes result.fetch("features"), "ibex/lsp.rb"
    refute_includes result.fetch("features"), "ibex/coverage.rb"
  end

  private

  def loaded_features_after(*arguments)
    stdout, stderr, process = Open3.capture3(
      RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", "-e", LOADED_FEATURES_SCRIPT, *arguments,
      chdir: File.expand_path("..", __dir__)
    )
    assert process.success?, stderr
    JSON.parse(stdout)
  end
end
