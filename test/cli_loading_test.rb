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
  DEFERRED_GENERATION_FEATURES = %w[
    ibex/bison_import.rb
    ibex/bison_import/importer.rb
    ibex/bison_import/tokenizer.rb
    ibex/frontend/diagnostic_recovery.rb
    ibex/frontend/dsl.rb
    ibex/frontend/formatter.rb
    ibex/generation_manifest.rb
    ibex/ir/migration.rb
    ibex/ir/validator.rb
    ibex/lalr/conflict_search.rb
    ibex/lalr/counterexample.rb
    ibex/runtime/cst.rb
    ibex/runtime/embedded_source.rb
    ibex/runtime/event_jsonl_tracer.rb
    ibex/runtime/generated_lexer.rb
    ibex/runtime/jsonl_tracer.rb
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
      },
      tempfile_loaded: $LOADED_FEATURES.any? { |path| File.basename(path) == "tempfile.rb" }
    )
  RUBY
  MINIMAL_RUNTIME_RECOVERY_SCRIPT = <<~RUBY
    require "ibex/runtime/parser"

    parser_class = Class.new(Ibex::Runtime::Parser) do
      tables = {
        format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
        tokens: {},
        token_names: { 0 => "$eof", 1 => "error" },
        actions: [{ 1 => [:shift, 1] }, { 0 => [:accept] }],
        gotos: [{}, {}],
        productions: []
      }.freeze
      define_singleton_method(:parser_tables) { tables }

      def next_token
        return false if @delivered

        @delivered = true
        [:BAD, nil]
      end

      def on_error(*) = nil
    end

    abort "recovery failed" unless parser_class.new.do_parse.nil?
    abort "CST leaked" if defined?(Ibex::Runtime::CST::ParseMemo)
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
      assert_empty result.fetch("features") & DEFERRED_GENERATION_FEATURES
      assert_equal false, result.fetch("tempfile_loaded")
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

  def test_minimal_runtime_parser_recovers_without_loading_cst
    _stdout, stderr, process = Open3.capture3(
      RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", "-e", MINIMAL_RUNTIME_RECOVERY_SCRIPT,
      chdir: File.expand_path("..", __dir__)
    )

    assert process.success?, stderr
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
