# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/cst_fidelity_property_harness"

class CSTFidelityPropertyTest < Minitest::Test
  SEED = 20_260_728
  GRAMMAR_CASES = 24

  def test_random_grammars_and_inputs_preserve_every_consumed_byte
    random = Random.new(SEED)

    GRAMMAR_CASES.times do |index|
      parser_class = CSTFidelityPropertyHarness.build(seed: SEED + index)
      assert_complete(parser_class, CSTFidelityPropertyHarness.valid_input(random), index)
      assert_lexical_error(parser_class, CSTFidelityPropertyHarness.lexical_error_input(random), index)
      assert_recovery(parser_class, CSTFidelityPropertyHarness.recovery_input(random), index)
      assert_repair(parser_class, CSTFidelityPropertyHarness.repair_input(random), index)
      assert_early_accept(index, CSTFidelityPropertyHarness.early_input(random))
    end
  end

  private

  def assert_complete(parser_class, source, index)
    result = parser_class.new.parse_with_syntax(source)

    assert_equal source.b, result.syntax_root.to_source, "valid grammar case #{index}"
    refute_predicate result.syntax_root, :contains_error?, "valid grammar case #{index}"
  end

  def assert_lexical_error(parser_class, source, index)
    result = parser_class.new.parse_with_syntax(source)

    assert_equal source.b, result.syntax_root.to_source, "lexical grammar case #{index}"
    assert_predicate result.syntax_root, :contains_error?, "lexical grammar case #{index}"
    assert(result.syntax_root.tokens.any? { |token| token.kind_name == "lexical_error_token" })
  end

  def assert_recovery(parser_class, source, index)
    result = parser_class.new.parse_with_syntax(source)

    assert_equal source.b, result.syntax_root.to_source, "recovery grammar case #{index}"
    assert result.syntax_root.green.flags.anybits?(Ibex::Runtime::CST::Flags::CONTAINS_SKIPPED)
    refute_empty result.diagnostics
  end

  def assert_repair(parser_class, source, index)
    parser = parser_class.new
    parser.repair_policy = Ibex::Runtime::RepairPolicy.new(success_shifts: 1)
    result = parser.parse_with_syntax(source)

    assert_equal source.b, result.syntax_root.to_source, "repair grammar case #{index}"
    flags = result.syntax_root.green.flags
    assert(
      flags.anybits?(
        Ibex::Runtime::CST::Flags::CONTAINS_MISSING |
        Ibex::Runtime::CST::Flags::CONTAINS_SKIPPED
      ),
      "repair grammar case #{index}"
    )
  end

  def assert_early_accept(index, source)
    parser_class = CSTFidelityPropertyHarness.build(seed: SEED + GRAMMAR_CASES + index, early: true)
    result = parser_class.new.parse_with_syntax(source)

    assert source.b.start_with?(result.syntax_root.to_source), "early grammar case #{index}"
    assert_predicate result.syntax_root, :incomplete_input?, "early grammar case #{index}"
  end
end
