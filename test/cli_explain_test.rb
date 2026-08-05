# frozen_string_literal: true

require_relative "test_helper"
require "json_schemer"
require "stringio"
require "tmpdir"

# rubocop:disable Metrics/ClassLength -- cases exercise one CLI analysis contract.
class CLIExplainTest < Minitest::Test
  SCHEMA = File.expand_path("../schema/explain-v1.schema.json", __dir__)

  def test_text_explains_every_conflict_in_deterministic_order
    with_grammar(expression_grammar) do |path|
      first = invoke(["explain", path])
      second = invoke(["explain", path])

      assert_equal 0, first.fetch(:status), first.fetch(:stderr)
      assert_equal first.fetch(:stdout), second.fetch(:stdout)
      assert_includes first.fetch(:stdout), "Ibex conflict explanation v1"
      assert_includes first.fetch(:stdout), "Matched conflicts: 4"
      assert_equal [1, 2, 3, 4], first.fetch(:stdout).scan(/^Conflict (\d+):/).flatten.map(&:to_i)
      assert_includes first.fetch(:stdout), "1. Reach state"
      assert_includes first.fetch(:stdout), "2. The lookahead permits these competing actions"
      assert_includes first.fetch(:stdout), "3. Resolution:"
      assert_match(/^\s+[|`]- /, first.fetch(:stdout))
    end
  end

  def test_json_has_a_versioned_schema_and_uses_stdout_only
    with_grammar(expression_grammar) do |path|
      result = invoke(["explain", "--format=json", "--algorithm=ielr", path])
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 0, result.fetch(:status)
      assert_empty result.fetch(:stderr)
      assert_equal "conflicts", document.fetch("ibex_explain")
      assert_equal 1, document.fetch("schema_version")
      assert_equal "ielr1", document.fetch("algorithm")
      schema = JSON.parse(File.read(SCHEMA))
      assert_empty JSONSchemer.schema(schema).validate(document).to_a
    end
  end

  def test_state_and_canonical_token_selectors_are_combined
    with_grammar(expression_grammar) do |path|
      all = JSON.parse(invoke(["explain", "--format=json", path]).fetch(:stdout))
      selected = all.fetch("conflicts").fetch(1)
      state = selected.fetch("state")
      token = selected.dig("token", "name")
      result = invoke(["explain", "--format=json", "--state=#{state}", "--token=#{token}", path])
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 0, result.fetch(:status), result.fetch(:stderr)
      refute_empty document.fetch("conflicts")
      assert(document.fetch("conflicts").all? { |conflict| conflict.fetch("state") == state })
      assert(document.fetch("conflicts").all? { |conflict| conflict.dig("token", "name") == token })
      assert_equal token, document.dig("selectors", "token", "query")
    end
  end

  def test_exact_display_name_selects_a_token_but_canonical_name_has_priority
    source = <<~GRAMMAR
      class P
      pragma extended
      token NUM OTHER
      display NUM "number"
      display OTHER "NUM"
      expect 1
      rule
      start: start start | NUM
      unused: OTHER
      end
    GRAMMAR
    with_grammar(source) do |path|
      displayed = JSON.parse(invoke(["explain", "--format=json", "--token=number", path]).fetch(:stdout))
      canonical = JSON.parse(invoke(["explain", "--format=json", "--token=NUM", path]).fetch(:stdout))

      assert_equal "NUM", displayed.dig("selectors", "token", "name")
      assert_equal "number", displayed.dig("selectors", "token", "display_name")
      assert_equal "NUM", canonical.dig("selectors", "token", "name")
      assert_equal "NUM", canonical.dig("selectors", "token", "query")
      refute_empty canonical.fetch("conflicts")
    end
  end

  def test_ambiguous_or_unknown_token_and_unknown_state_are_diagnostics
    ambiguous = <<~GRAMMAR
      class P
      pragma extended
      token A B
      display A "word"
      display B "word"
      rule
      start: A | B
      end
    GRAMMAR
    with_grammar(ambiguous) do |path|
      result = invoke(["explain", "--token=word", path])
      assert_equal 1, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_equal "(cli):1:1: token display name \"word\" is ambiguous; use one of: A, B\n", result.fetch(:stderr)

      result = invoke(["explain", "--token=missing", path])
      assert_equal 1, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_includes result.fetch(:stderr), "unknown token \"missing\""

      result = invoke(["explain", "--state=999", path])
      assert_equal 1, result.fetch(:status)
      assert_empty result.fetch(:stdout)
      assert_equal "(cli):1:1: unknown automaton state 999\n", result.fetch(:stderr)
    end
  end

  def test_no_conflicts_and_selector_mismatch_are_successful_empty_views
    with_grammar("class P\nrule\nstart: TOKEN\nend\n") do |path|
      text = invoke(["explain", path])
      assert_equal 0, text.fetch(:status)
      assert_includes text.fetch(:stdout), "Matched conflicts: 0"
      assert_includes text.fetch(:stdout), "No conflicts matched the selectors."
    end

    with_grammar(expression_grammar) do |path|
      result = invoke(["explain", "--format=json", "--state=0", "--token=NUM", path])
      document = JSON.parse(result.fetch(:stdout))
      assert_equal 0, result.fetch(:status)
      assert_equal 0, document.dig("summary", "matched_conflicts")
      assert_empty document.fetch("conflicts")
    end
  end

  def test_search_budget_distinguishes_bounded_absence_from_configuration_exhaustion
    with_grammar(dangling_else_grammar) do |path|
      result = invoke(["explain", "--format=json", "--counterexample-max-tokens=8", path])
      document = JSON.parse(result.fetch(:stdout))

      assert_equal 0, result.fetch(:status), result.fetch(:stderr)
      assert_equal 1, document.dig("summary", "nonunifying_witnesses")
      assert_equal 0, document.dig("summary", "inconclusive_searches")
      assert_equal "nonunifying_witness", document.dig("conflicts", 0, "witness", "kind")
      assert_equal "not_found", document.dig("conflicts", 0, "witness", "search", "status")
      refute document.dig("conflicts", 0, "witness", "search", "exhausted")

      text = invoke(["explain", "--counterexample-max-configurations=100", path]).fetch(:stdout)
      assert_includes text, "Inconclusive reachability witness"
      assert_includes text, "Search exhausted after 100 configurations; classification is inconclusive."
    end
  end

  def test_one_configuration_budget_is_schema_valid_and_explicitly_inconclusive
    with_grammar(expression_grammar) do |path|
      result = invoke(["explain", "--format=json", "--counterexample-max-configurations=1", path])
      document = JSON.parse(result.fetch(:stdout))
      witness = document.dig("conflicts", 0, "witness")

      assert_equal 0, result.fetch(:status), result.fetch(:stderr)
      assert_equal document.dig("summary", "matched_conflicts"),
                   document.dig("summary", "inconclusive_searches")
      assert_equal 0, document.dig("summary", "nonunifying_witnesses")
      assert_equal "inconclusive", witness.fetch("kind")
      assert_equal({ "status" => "exhausted", "explored" => 1, "exhausted" => true,
                     "bounds" => { "max_tokens" => 32, "max_configurations" => 1 } },
                   witness.fetch("search"))
      schema = JSON.parse(File.read(SCHEMA))
      assert_empty JSONSchemer.schema(schema).validate(document).to_a
    end
  end

  def test_extended_mode_accepts_extended_grammar_without_a_pragma
    source = <<~GRAMMAR
      class P
      token NUM
      rule
      start: NUM?
      end
    GRAMMAR
    with_grammar(source) do |path|
      default = invoke(["explain", path])
      assert_equal 1, default.fetch(:status)
      assert_empty default.fetch(:stdout)

      extended = invoke(["explain", "--mode=extended", "--format=json", path])
      assert_equal 0, extended.fetch(:status), extended.fetch(:stderr)
      assert_empty JSON.parse(extended.fetch(:stdout)).fetch("conflicts")
    end
  end

  def test_midrule_conflict_origins_are_visible_in_text_and_json
    source = <<~GRAMMAR
      class P
      pragma extended
      rule
      start: A { result = val[0] } B | A B
      end
    GRAMMAR
    with_grammar(source) do |path|
      canonical_path = File.realpath(path)
      text = invoke(["explain", path])
      assert_equal 0, text.fetch(:status), text.fetch(:stderr)
      assert_includes text.fetch(:stdout), "Midrule action origin: #{canonical_path}:4:10"

      result = invoke(["explain", "--format=json", path])
      document = JSON.parse(result.fetch(:stdout))
      assert_equal [{ "file" => canonical_path, "line" => 4, "column" => 10 }],
                   document.dig("conflicts", 0, "midrule_origins")
      schema = JSON.parse(File.read(SCHEMA))
      assert_empty JSONSchemer.schema(schema).validate(document).to_a
    end
  end

  def test_help_and_option_errors_are_scoped_to_the_subcommand
    main_help = invoke(%w[--help])
    assert_includes main_help.fetch(:stdout), "explain"

    help = invoke(%w[explain --help])
    assert_equal 0, help.fetch(:status)
    options = %w[
      --state --token --format --algorithm --mode --counterexample-max-tokens --counterexample-max-configurations
    ]
    options.each do |option|
      assert_includes help.fetch(:stdout), option
    end

    invalid = invoke(%w[explain --format=yaml])
    assert_equal 1, invalid.fetch(:status)
    assert_empty invalid.fetch(:stdout)
    assert_includes invalid.fetch(:stderr), "invalid argument: --format=yaml"

    invalid_budget = invoke(%w[explain --counterexample-max-tokens=0])
    assert_equal 1, invalid_budget.fetch(:status)
    assert_empty invalid_budget.fetch(:stdout)
    assert_equal "(cli):1:1: --counterexample-max-tokens must be positive\n", invalid_budget.fetch(:stderr)
  end

  private

  def invoke(arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Ibex::CLI.start(arguments, stdout: stdout, stderr: stderr)
    { status: status, stdout: stdout.string, stderr: stderr.string }
  end

  def with_grammar(source)
    Dir.mktmpdir("ibex-explain") do |directory|
      path = File.join(directory, "grammar.y")
      File.write(path, source)
      yield path
    end
  end

  def expression_grammar
    <<~GRAMMAR
      class P
      token NUM
      expect 4
      rule
      expr: expr '+' expr
          | expr '*' expr
          | NUM
      end
    GRAMMAR
  end

  def dangling_else_grammar
    <<~GRAMMAR
      class P
      token IF THEN ELSE ID
      expect 1
      rule
      stmt: IF expr THEN stmt
          | IF expr THEN stmt ELSE stmt
          | ID
      expr: ID
      end
    GRAMMAR
  end
end
# rubocop:enable Metrics/ClassLength
