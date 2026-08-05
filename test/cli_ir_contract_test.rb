# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIIRContractTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("fixtures/ir", __dir__)

  def test_v3_grammar_and_automaton_resume_to_identical_source_without_original_grammar
    Dir.mktmpdir("ibex-ir-contract") do |directory|
      grammar_output = File.join(directory, "grammar.rb")
      automaton_output = File.join(directory, "automaton.rb")

      assert_equal 0, run_cli(["--from=grammar-ir", "-o", grammar_output, fixture("grammar-v3.json")])
      assert_equal 0, run_cli(["--from=automaton-ir", "-o", automaton_output, fixture("automaton-v3.json")])

      assert_equal File.binread(grammar_output), File.binread(automaton_output)
    end
  end

  def test_v3_grammar_contract_selects_automaton_construction
    output = StringIO.new
    status = run_cli(
      ["--from=grammar-ir", "--emit=automaton-ir", fixture("grammar-v3.json")],
      stdout: output
    )

    assert_equal 0, status
    automaton = Ibex::IR::Validator.validate(output.string)
    assert_equal "ielr1", automaton.algorithm
    assert_equal "shared", automaton.entry_construction
  end

  def test_v3_static_tooling_does_not_execute_embedded_actions
    Dir.mktmpdir("ibex-ir-contract-static") do |directory|
      path = File.join(directory, "grammar.json")
      document = JSON.parse(File.binread(fixture("grammar-v3.json")))
      document.fetch("productions").each do |production|
        production["action"]["code"] = 'raise "embedded action executed"' if production["action"]
      end
      File.binwrite(path, JSON.pretty_generate(document))
      output = StringIO.new

      assert_equal 0, run_cli(["--from=grammar-ir", "--emit=sets", path], stdout: output)
      assert JSON.parse(output.string).fetch("first").key?("start")
    end
  end

  def test_matching_cli_contract_is_accepted_and_conflicting_cli_is_rejected_for_grammar_ir
    assert_equal 0, run_cli(
      ["--from=grammar-ir", "--algorithm=ielr", "--emit=automaton-ir", fixture("grammar-v3.json")],
      stdout: StringIO.new
    )

    errors = StringIO.new
    assert_equal 1, run_cli(
      ["--from=grammar-ir", "--algorithm=lr1", "--emit=automaton-ir", fixture("grammar-v3.json")],
      stderr: errors
    )
    assert_includes errors.string, "configuration conflict for parser.algorithm"
    assert_includes errors.string, "golden-v3.y:2:1 selected :ielr"
  end

  def test_constructed_automaton_inputs_reject_construction_flags_for_every_readable_version
    %w[automaton-v1.json automaton-v2.json automaton-v2-migrated-v3.json].each do |name|
      { "--algorithm=lalr" => "--algorithm", "--entry-isolation" => "--entry-isolation" }.each do |flag, label|
        errors = StringIO.new
        status = run_cli(["--from=automaton-ir", flag, fixture(name)], stderr: errors)

        assert_equal 1, status, "#{name} with #{flag}"
        assert_includes errors.string, "#{label} cannot be combined with --from=automaton-ir"
      end
    end
  end

  def test_v1_v2_and_migrated_v3_automata_generate_identical_source
    Dir.mktmpdir("ibex-automaton-readers") do |directory|
      outputs = %w[automaton-v1.json automaton-v2.json automaton-v2-migrated-v3.json].map do |name|
        output = File.join(directory, "#{name}.rb")
        assert_equal 0, run_cli(["--from=automaton-ir", "-o", output, fixture(name)])
        File.binread(output)
      end

      normalized = outputs.map { |source| without_embedded_grammar_identity(source) }
      assert_equal normalized.fetch(0), normalized.fetch(1)
      assert_equal normalized.fetch(0), normalized.fetch(2)
    end
  end

  def test_v3_manifest_records_contract_digest_construction_and_effective_origins
    Dir.mktmpdir("ibex-ir-contract-manifest") do |directory|
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      status = run_cli(["--from=grammar-ir", "--manifest=#{manifest}", "-o", parser, fixture("grammar-v3.json")])

      assert_equal 0, status
      document = Ibex::GenerationManifest.validate(File.binread(manifest))
      options = document.fetch("options")
      assert_equal 3, options.dig("grammar_ir", "schema_version")
      assert_match(/\Asha256:[0-9a-f]{64}\z/, options.dig("grammar_ir", "digest"))
      assert_equal "ielr", options.dig("grammar_ir", "parser_contract", "algorithm", "value")
      assert_equal "ielr1", options.dig("automaton_ir", "algorithm")
      assert_equal "shared", options.dig("automaton_ir", "entry_construction")
      assert_equal "grammar_contract", options.dig("automaton_ir", "construction_authority")
      algorithm = options.fetch("effective_configuration").find do |entry|
        entry.fetch("key") == "parser.algorithm"
      end
      assert_equal "grammar", algorithm.dig("origin", "kind")
      assert_equal "golden-v3.y", algorithm.dig("origin", "location", "file")
    end
  end

  def test_migrated_automaton_manifest_keeps_unspecified_contract_separate_from_embedded_facts
    Dir.mktmpdir("ibex-migrated-automaton-manifest") do |directory|
      input = File.join(directory, "automaton.json")
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      document = JSON.parse(File.binread(fixture("automaton-v2-migrated-v3.json")))
      document["algorithm"] = "ielr1"
      File.binwrite(input, JSON.pretty_generate(document))

      assert_equal 0, run_cli(
        ["--from=automaton-ir", "--manifest=#{manifest}", "-o", parser, input]
      )
      options = Ibex::GenerationManifest.validate(File.binread(manifest)).fetch("options")
      assert_equal "ielr1", options.dig("automaton_ir", "algorithm")
      assert_equal "unknown", options.dig("automaton_ir", "entry_construction")
      assert_equal "embedded_automaton", options.dig("automaton_ir", "construction_authority")
      options.fetch("grammar_ir").fetch("parser_contract").each_value do |entry|
        assert_equal({ "explicit" => false, "loc" => nil, "value" => nil }, entry)
      end
      effective_keys = options.fetch("effective_configuration").map { |entry| entry.fetch("key") }
      refute_includes effective_keys, "parser.algorithm"
      refute_includes effective_keys, "parser.entries"
    end
  end

  private

  def run_cli(arguments, stdout: StringIO.new, stderr: StringIO.new)
    Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
  end

  def fixture(name)
    File.join(FIXTURE_ROOT, name)
  end

  def without_embedded_grammar_identity(source)
    source
      .sub(/Generated by Ibex [0-9a-f]+/, "Generated by Ibex DIGEST")
      .sub(/GRAMMAR_DIGEST = "sha256:[0-9a-f]{64}"/, 'GRAMMAR_DIGEST = "sha256:DIGEST"')
  end
end
