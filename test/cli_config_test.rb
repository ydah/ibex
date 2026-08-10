# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

# rubocop:disable Metrics/ClassLength -- configuration command cases cover the static trust boundary.
class CLIConfigTest < Minitest::Test
  def test_default_only_source_explains_every_registry_key
    with_grammar("class P\nrule\nstart: TOKEN\nend\n") do |path|
      result = invoke(["config", "--format=json", path])
      document = JSON.parse(result.fetch(:stdout))
      entries = document.fetch("configuration")

      assert_equal 0, result.fetch(:status)
      assert_equal "static-no-user-code", document.fetch("trust")
      assert_equal "ok", document.fetch("status")
      assert_equal(Ibex::Configuration::Registry.keys.map(&:name).sort, entries.map { |entry| entry.fetch("key") })
      algorithm = configuration(document, "parser.algorithm")
      assert_equal "lalr", algorithm.fetch("value")
      assert_equal "builtin", algorithm.dig("origin", "kind")
      assert_equal "implicit", algorithm.fetch("selection")
      assert_equal "canonical", algorithm.fetch("conformance")
    end
  end

  def test_current_parser_contract_and_matching_cli_keep_source_evidence
    result = invoke([
                      "config", "--from=grammar-ir", "--algorithm=ielr", "--format=json", fixture("grammar.json")
                    ])
    document = JSON.parse(result.fetch(:stdout))
    algorithm = configuration(document, "parser.algorithm")

    assert_equal 0, result.fetch(:status)
    assert_equal "ielr", algorithm.fetch("value")
    assert_equal "grammar", algorithm.dig("origin", "kind")
    assert_equal "golden.y", algorithm.dig("origin", "location", "file")
    assert_equal(%w[grammar cli], algorithm.fetch("evidence").map { |entry| entry.fetch("source") })
    assert(algorithm.fetch("evidence").all? { |entry| entry.fetch("status") == "accepted" })
    assert_includes algorithm.fetch("evidence").last.fetch("reason"), "matches"
  end

  def test_source_cst_trivia_contract_is_explained_with_origin
    source = <<~GRAMMAR
      class P
      pragma cst
      parser
        cst_trivia balanced
      end
      rule
      start: TOKEN
      end
    GRAMMAR
    with_grammar(source) do |path|
      result = invoke(["config", "--format=json", path])
      document = JSON.parse(result.fetch(:stdout))
      trivia = configuration(document, "cst.trivia")

      assert_equal 0, result.fetch(:status), result.fetch(:stderr)
      assert_equal "balanced", trivia.fetch("value")
      assert_equal "grammar", trivia.dig("origin", "kind")
      assert_equal [4, 3], trivia.dig("origin", "location").values_at("line", "column")
      assert_equal "canonical", trivia.fetch("conformance")
    end
  end

  def test_current_conflict_is_positioned_structured_and_nonzero_in_both_languages
    results = %w[en ja].to_h do |language|
      [language, invoke([
                          "--lang=#{language}", "config", "--from=grammar-ir", "--algorithm=lalr", "--format=json",
                          fixture("grammar.json")
                        ])]
    end
    english = JSON.parse(results.fetch("en").fetch(:stdout))
    japanese = JSON.parse(results.fetch("ja").fetch(:stdout))
    algorithm = configuration(english, "parser.algorithm")
    conflict = english.fetch("conflicts").fetch(0)

    assert_conflict_statuses(results)
    assert_equal english, japanese
    assert_equal "conflict", english.fetch("status")
    assert_equal "ielr", conflict.dig("declared", "value")
    assert_equal "golden.y", conflict.dig("declared", "origin", "location", "file")
    assert_equal "lalr", conflict.dig("requested", "value")
    assert_equal "conflicting", algorithm.fetch("evidence").last.fetch("status")
    assert_match(/golden\.y:2:1: configuration conflict/, results.fetch("en").fetch(:stderr))
    assert_match(/エラー: golden\.y:2:1: configuration conflict/, results.fetch("ja").fetch(:stderr))
  end

  def test_current_grammar_ir_records_parser_contract_facts
    result = invoke(["config", "--from=grammar-ir", "--format=json", fixture("grammar.json")])
    document = JSON.parse(result.fetch(:stdout))

    assert_equal 0, result.fetch(:status)
    %w[parser.algorithm parser.entries cst.trivia].each do |key|
      entry = configuration(document, key)
      assert_equal "recorded", entry.dig("recording", "state"), key
      assert_match(/current Grammar IR records an explicit parser contract/, entry.dig("recording", "reason"), key)
    end
  end

  def test_source_duplicate_and_conflicting_compatibility_evidence_is_visible
    source = <<~GRAMMAR
      class P
      options omit_action_call
      options no_omit_action_call
      options no_omit_action_call
      rule
      start: TOKEN
      end
    GRAMMAR
    with_grammar(source) do |path|
      result = invoke(["config", "--format=json", path])
      entry = configuration(JSON.parse(result.fetch(:stdout)), "actions.omit_calls")

      assert_equal 0, result.fetch(:status)
      assert_equal false, entry.fetch("value")
      assert_equal(%w[conflicting duplicate accepted], entry.fetch("evidence").map { |item| item.fetch("status") })
      assert(entry.fetch("evidence").all? { |item| item.key?("location") })
    end
  end

  def test_contained_resolver_rejects_parent_and_symlink_escape
    Dir.mktmpdir("ibex-config-containment") do |directory|
      root_directory = File.join(directory, "root")
      FileUtils.mkdir_p(root_directory)
      outside = write(directory, "outside.y", "fragment\nrule\nhelper: TOKEN\nend\n")
      parent = write(root_directory, "parent.y", root_with_include("../outside.y"))
      parent_result = invoke(["config", "--format=json", parent])

      assert_equal 1, parent_result.fetch(:status)
      assert_includes parent_result.fetch(:stderr), "parent traversal"

      link = File.join(root_directory, "escape.y")
      File.symlink(outside, link)
      symlink = write(root_directory, "symlink.y", root_with_include("escape.y"))
      symlink_result = invoke(["config", "--format=json", symlink])

      assert_equal 1, symlink_result.fetch(:status)
      assert_includes symlink_result.fetch(:stderr), "outside the root grammar directory"
    end
  rescue NotImplementedError, Errno::EPERM
    skip "symlinks are not available"
  end

  def test_static_report_never_executes_actions_or_user_sections
    source = <<~GRAMMAR
      class NoExec
      pragma extended
      token TOKEN
      lexer
        TOKEN /token/ { raise "generated lexer action executed" }
      end
      rule
      start: TOKEN { raise "semantic action executed" }
      end
      ---- header
      raise "header executed"
      ---- inner
      raise "inner executed"
      ---- footer
      raise "footer executed"
    GRAMMAR
    with_grammar(source) do |path|
      result = invoke(["config", "--format=json", path])

      assert_equal 0, result.fetch(:status)
      assert_equal "static-no-user-code", JSON.parse(result.fetch(:stdout)).fetch("trust")
      assert_empty result.fetch(:stderr)
    end
  end

  def test_cli_instance_reuse_does_not_leak_config_options_or_break_zero_exit_information
    with_grammar("class P\nrule\nstart: TOKEN\nend\n") do |path|
      stdout = StringIO.new
      stderr = StringIO.new
      cli = Ibex::CLI.new(stdout: stdout, stderr: stderr)

      assert_equal 0, cli.run(["config", "--algorithm=ielr", "--format=json", path])
      first = JSON.parse(stdout.string)
      assert_equal "ielr", configuration(first, "parser.algorithm").fetch("value")
      reset(stdout)

      assert_equal 0, cli.run(["config", "--format=json", path])
      second = JSON.parse(stdout.string)
      assert_equal "lalr", configuration(second, "parser.algorithm").fetch("value")
      assert_equal "builtin", configuration(second, "parser.algorithm").dig("origin", "kind")
      reset(stdout)

      assert_equal 0, cli.run(["--version"])
      assert_equal "ibex #{Ibex::VERSION}\n", stdout.string
      assert_empty stderr.string
    end
  end

  private

  def assert_conflict_statuses(results)
    assert_equal 1, results.fetch("en").fetch(:status)
    assert_equal 1, results.fetch("ja").fetch(:status)
  end

  def fixture(name)
    File.expand_path("fixtures/ir/#{name}", __dir__)
  end

  def configuration(document, key)
    document.fetch("configuration").find { |entry| entry.fetch("key") == key } || flunk("missing #{key}")
  end

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end

  def with_grammar(source)
    Dir.mktmpdir("ibex-config") do |directory|
      yield write(directory, "grammar.y", source)
    end
  end

  def write(directory, relative, source)
    path = File.join(directory, relative)
    File.binwrite(path, source)
    path
  end

  def root_with_include(path)
    "class P\npragma extended\ninclude #{path.dump}\nrule\nstart: helper\nend\n"
  end

  def reset(io)
    io.truncate(0)
    io.rewind
  end
end
# rubocop:enable Metrics/ClassLength
