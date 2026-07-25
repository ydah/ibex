# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIIncludesTest < Minitest::Test
  def test_pipeline_diagnostics_and_mode_gate_resolve_fragments
    with_include_grammar do |root, fragment, directory|
      output = StringIO.new
      result = invoke(["--mode=extended", "--emit=grammar-ir", root], stdout: output)
      document = JSON.parse(output.string)

      assert_equal 0, result.fetch(:status)
      assert_equal File.realpath(directory), document.fetch("source_provenance").fetch("root")
      helper = production_for(document, "helper")
      chain = helper.fetch("expansion").fetch("include_chain")
      chain_files = chain.map { |entry| entry.fetch("file") }
      assert_equal [File.realpath(fragment)], chain_files

      diagnostics = StringIO.new
      result = invoke(["diagnose", "--mode=extended", "--format=json", root], stdout: diagnostics)
      assert_equal 0, result.fetch(:status)
      assert_equal true, JSON.parse(diagnostics.string).fetch("success")

      rejected = invoke(["-C", root])
      assert_equal 1, rejected.fetch(:status)
      assert_match(/includes require extended mode/, rejected.fetch(:stderr))
    end
  end

  def test_explain_samples_and_errors_use_the_same_resolver
    with_include_grammar do |root, _fragment, directory|
      explanation = StringIO.new
      result = invoke(["explain", "--mode=extended", "--format=json", root], stdout: explanation)
      assert_equal 0, result.fetch(:status)
      assert_kind_of Hash, JSON.parse(explanation.string)

      samples = StringIO.new
      result = invoke(["samples", "--mode=extended", "--count=1", root], stdout: samples)
      assert_equal 0, result.fetch(:status)
      assert_equal 1, samples.string.lines.length

      messages = File.join(directory, "grammar.messages")
      result = invoke(["errors", "--mode=extended", "--update=#{messages}", root])
      assert_equal 0, result.fetch(:status)
      assert File.file?(messages)
    end
  end

  private

  def with_include_grammar
    Dir.mktmpdir("ibex-cli-includes") do |directory|
      root = File.join(directory, "root.y")
      fragment = File.join(directory, "fragment.y")
      File.write(root, "class P\ninclude \"fragment.y\"\nrule\nstart: helper\nend\n")
      File.write(fragment, "fragment\nrule\nhelper: TOKEN\nend\n")
      yield root, fragment, directory
    end
  end

  def production_for(document, lhs_name)
    symbols = document.fetch("symbols").to_h { |symbol| [symbol.fetch("id"), symbol.fetch("name")] }
    document.fetch("productions").find { |production| symbols.fetch(production.fetch("lhs")) == lhs_name }
  end

  def invoke(arguments, stdout: StringIO.new)
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stderr: stderr.string }
  end
end
