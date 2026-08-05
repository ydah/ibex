# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tool/profile/lexer_profiler"

class LexerProfilerTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  FIXTURES = File.join(ROOT, "test/fixtures/lexer_profile")

  def test_ruby_regexp_alternation_is_observed_separately_from_cross_rule_longest_match
    result = profile("alternation")

    lengths = result.dig("token_lengths", "sample").map { |token| token.fetch("bytes") }
    assert_equal [0], result.dig("structure", "alternation_rule_ids")
    assert_equal [1, 1], lengths
    assert_equal 2, result.dig("token_lengths", "count")
  end

  def test_lazy_quantifier_and_nested_quantifier_warning_are_recorded
    lazy = profile("lazy-quantifier")
    nested = profile("nested-quantifier")

    lazy_lengths = lazy.dig("token_lengths", "sample").map { |token| token.fetch("bytes") }
    assert_equal [0], lazy.dig("structure", "lazy_rule_ids")
    assert_equal [1, 1, 1], lazy_lengths
    assert_equal [{ "type" => "redos", "rule_id" => 0 }], nested.dig("structure", "regexp_warnings")
  end

  def test_long_common_prefix_selects_the_only_complete_rule
    result = profile("long-common-prefix")

    assert_equal fixture_input("long-common-prefix").bytesize,
                 result.dig("token_lengths", "maximum_bytes")
    assert_equal "RIGHT", result.dig("token_lengths", "sample", 0, "token")
  end

  def test_state_mutation_sources_and_parser_feedback_are_explicit
    lexer_action = profile("stateful-string")
    parser_action = profile("parser-feedback")

    assert_equal [0, 2], lexer_action.dig("structure", "state_mutation_sources", "lexer_rule_ids")
    refute lexer_action.dig("structure", "parser_to_lexer_feedback")
    assert_empty parser_action.dig("structure", "state_mutation_sources", "lexer_rule_ids")
    refute_empty parser_action.dig("structure", "state_mutation_sources", "parser_production_ids")
    assert parser_action.dig("structure", "parser_to_lexer_feedback")
    assert_equal "not_measured", parser_action.dig("incremental_full_scan", "status")
  end

  def test_chunk_boundary_and_incremental_full_scan_are_observations
    input = fixture_input("chunk-boundary") * 129
    result = profile("chunk-boundary", input: input, streaming: true)

    assert_operator input.bytesize, :>, Ibex::Runtime::LexerInput::DEFAULT_CHUNK_SIZE
    assert_operator result.dig("streaming", "peak_buffer_bytes"), :>,
                    Ibex::Runtime::LexerInput::DEFAULT_CHUNK_SIZE
    assert_equal input.bytesize, result.dig("streaming", "source_bytes_read")
    assert_equal "measured", result.dig("incremental_full_scan", "status")
    assert_equal 1.0, result.dig("incremental_full_scan", "share")
  end

  def test_unicode_property_and_runtime_measurements_are_diagnostic_only
    result = profile("unicode-property", streaming: false, incremental: false)

    assert_equal fixture_input("unicode-property").bytesize,
                 result.dig("token_lengths", "maximum_bytes")
    result.fetch("runtime_observations").each_value do |observation|
      assert_equal "observation", observation.fetch("status")
      refute observation.fetch("release_gate")
    end
  end

  private

  def profile(name, input: fixture_input(name), streaming: true, incremental: true)
    file = File.join(FIXTURES, "#{name}.y")
    source = File.binread(file)
    ast = Ibex::Frontend::Parser.new(source, file: file, mode: :extended).parse
    grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
    Ibex::Profile::LexerProfiler.new.profile(
      grammar: grammar, input: input, streaming: streaming, incremental: incremental, file: file
    )
  end

  def fixture_input(name)
    File.read(File.join(FIXTURES, "#{name}.txt"), encoding: Encoding::UTF_8).delete_suffix("\n")
  end
end
