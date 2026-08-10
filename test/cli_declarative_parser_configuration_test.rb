# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"
require "tmpdir"

class CLIDeclarativeParserConfigurationTest < Minitest::Test
  ALGORITHMS = {
    "slr" => "slr", "lalr" => "lalr1", "ielr" => "ielr1", "lr1" => "lr1"
  }.freeze

  def test_canonical_source_generation_honors_every_declared_algorithm_and_entry_mode
    ALGORITHMS.each do |declared, persisted|
      %w[shared isolated].each do |entries|
        with_grammar(parser_grammar(["algorithm #{declared}", "entries #{entries}"], multiple_starts: true)) do |path|
          result = invoke(["--emit=automaton-ir", path])
          automaton = Ibex::IR::Validator.validate(result.fetch(:stdout))

          assert_equal 0, result.fetch(:status), result.fetch(:stderr)
          assert_equal persisted, automaton.algorithm
          assert_equal entries, automaton.entry_construction
          assert_equal 1, automaton.schema_version
          assert_equal declared.to_sym, automaton.grammar.parser_contract.algorithm.value
          assert_equal entries.to_sym, automaton.grammar.parser_contract.entries.value
        end
      end
    end
  end

  def test_canonical_source_generation_honors_isolated_entries_and_manifest_evidence
    with_grammar(parser_grammar("entries isolated", multiple_starts: true)) do |path, directory|
      parser = File.join(directory, "parser.rb")
      manifest = File.join(directory, "parser.ibex.json")
      result = invoke(["--manifest=#{manifest}", "-o", parser, path])
      assert_equal 0, result.fetch(:status), result.fetch(:stderr)

      options = Ibex::GenerationManifest.validate_file(manifest).fetch("options")
      entries = options.fetch("effective_configuration").find do |entry|
        entry.fetch("key") == "parser.entries"
      end

      assert_equal "isolated", options.dig("automaton_ir", "entry_construction")
      assert_equal "isolated", options.dig("grammar_ir", "parser_contract", "entries", "value")
      assert_equal "grammar", entries.dig("origin", "kind")
    end
  end

  def test_matching_generation_flag_is_accepted_and_conflict_is_positioned
    with_grammar(parser_grammar("algorithm ielr")) do |path|
      matching = invoke(["--algorithm=ielr", "--emit=automaton-ir", path])
      conflict = invoke(["--algorithm=lr1", "--emit=automaton-ir", path])

      assert_equal 0, matching.fetch(:status), matching.fetch(:stderr)
      assert_equal "ielr1", JSON.parse(matching.fetch(:stdout)).fetch("algorithm")
      assert_equal 1, conflict.fetch(:status)
      assert_match(/#{Regexp.escape(path)}:4:3 selected :ielr/, conflict.fetch(:stderr))
    end
  end

  def test_config_reports_source_contract_matching_evidence_and_positioned_conflicts
    with_grammar(parser_grammar(["algorithm ielr", "entries shared"])) do |path|
      matching = invoke(["config", "--algorithm=ielr", "--format=json", path])
      document = JSON.parse(matching.fetch(:stdout))
      algorithm = document.fetch("configuration").find do |entry|
        entry.fetch("key") == "parser.algorithm"
      end

      assert_equal 0, matching.fetch(:status)
      assert_equal "ielr", algorithm.fetch("value")
      assert_equal "grammar", algorithm.dig("origin", "kind")
      assert_equal [4, 3], algorithm.dig("origin", "location").values_at("line", "column")
      assert_equal(%w[grammar cli], algorithm.fetch("evidence").map { |entry| entry.fetch("source") })

      conflict = invoke(["config", "--algorithm=lr1", "--format=json", path])
      assert_equal 1, conflict.fetch(:status)
      assert_match(/#{Regexp.escape(path)}:4:3: configuration conflict/, conflict.fetch(:stderr))
    end
  end

  def test_metrics_uses_the_declaration_by_default_and_reports_an_explicit_noncanonical_override
    with_grammar(parser_grammar("algorithm ielr")) do |path|
      declared = invoke(["metrics", path])
      alternate = invoke(["metrics", "--algorithm=lr1", path])

      assert_equal 0, declared.fetch(:status), declared.fetch(:stderr)
      assert_equal 0, alternate.fetch(:status), alternate.fetch(:stderr)
      assert_equal "ielr1", JSON.parse(declared.fetch(:stdout)).fetch("algorithm")
      assert_equal "lr1", JSON.parse(alternate.fetch(:stdout)).fetch("algorithm")
      assert_includes alternate.fetch(:stderr), "parser.algorithm declared=ielr selected=lr1"
      assert_includes alternate.fetch(:stderr), "canonical_generation=false"
    end
  end

  private

  def parser_grammar(setting, multiple_starts: false)
    starts = multiple_starts ? "start first second\n" : ""
    rules = multiple_starts ? "first: FIRST\nsecond: SECOND" : "start: TOKEN"
    settings = Array(setting).join("\n  ")
    <<~GRAMMAR
      class P
      pragma extended
      parser
        #{settings}
      end
      #{starts}rule
      #{rules}
      end
    GRAMMAR
  end

  def with_grammar(source)
    Dir.mktmpdir("ibex-declarative-parser") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      yield path, directory
    end
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end
end
