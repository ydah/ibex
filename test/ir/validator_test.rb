# frozen_string_literal: true

require_relative "../test_helper"

class IRValidatorTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("../fixtures/ir", __dir__)

  def test_validates_and_loads_current_grammar
    value = Ibex::IR::Validator.validate(fixture("grammar.json"))

    assert_instance_of Ibex::IR::Grammar, value
    assert_equal Ibex::IR::SCHEMA_VERSION, value.schema_version
    assert_equal "GoldenFixtureParser", value.class_name
    refute_nil value.parser_contract
  end

  def test_validates_and_loads_current_automaton
    value = Ibex::IR::Validator.validate(fixture("automaton.json"))

    assert_instance_of Ibex::IR::Automaton, value
    assert_equal Ibex::IR::SCHEMA_VERSION, value.schema_version
    assert_equal Ibex::IR::SCHEMA_VERSION, value.grammar.schema_version
    assert_equal "ielr1", value.algorithm
    assert_equal "shared", value.entry_construction
  end

  def test_current_contract_distinguishes_unspecified_from_builtin_defaults
    document = parsed_fixture("grammar.json")
    document.dig("parser_contract", "algorithm").update("value" => "lalr", "explicit" => false, "loc" => nil)

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.parser_contract.algorithm.value must be nil", error.message
  end

  def test_current_contract_requires_a_source_location_for_explicit_values
    document = parsed_fixture("grammar.json")
    document.dig("parser_contract", "algorithm")["loc"] = nil

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.parser_contract.algorithm.loc must be an object", error.message
  end

  def test_current_contract_is_closed_and_cst_aware
    document = parsed_fixture("grammar.json")
    document.fetch("parser_contract")["future"] = {}

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
    assert_equal "(ir):1:1: $.parser_contract has unsupported field \"future\"", error.message

    document = parsed_fixture("grammar.json")
    document.fetch("options").delete("cst")
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
    assert_equal "(ir):1:1: $.parser_contract.cst_trivia requires options.cst", error.message
  end

  def test_automaton_must_match_the_embedded_parser_contract
    document = parsed_fixture("automaton.json")
    document["algorithm"] = "lalr1"
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
    assert_equal "(ir):1:1: $.algorithm must match the embedded parser contract", error.message

    document = parsed_fixture("automaton.json")
    document["entry_construction"] = "isolated"
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
    assert_equal "(ir):1:1: $.entry_construction must match the embedded parser contract", error.message
  end

  def test_grammar_digest_covers_the_parser_contract
    document = parsed_fixture("automaton.json")
    document.dig("grammar", "parser_contract", "cst_trivia")["value"] = "leading"

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_match(/\$\.grammar_digest does not match the embedded grammar/, error.message)
  end

  def test_rejects_old_and_unknown_schema_versions
    [2, 3, 99].each do |version|
      error = assert_raises(Ibex::Error) do
        Ibex::IR::Validator.validate(JSON.generate(ibex_ir: "grammar", schema_version: version))
      end

      assert_equal "(ir):1:1: unsupported schema_version #{version}; expected the current format (1)", error.message
    end
  end

  def test_rejects_missing_state_references
    document = parsed_fixture("automaton.json")
    document.fetch("states").first.fetch("transitions")["NUMBER"] = 99

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.states[0].transitions.NUMBER references missing state id 99", error.message
  end

  def test_rejects_unknown_entry_construction
    document = parsed_fixture("automaton.json")
    document["entry_construction"] = "unknown"

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_match(/\$\.entry_construction must be one of shared, isolated/, error.message)
  end

  def test_rejects_removed_grammar_fields
    document = parsed_fixture("grammar.json")
    document["migration"] = nil

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $ has unsupported field \"migration\"", error.message
  end

  private

  def fixture(name)
    File.read(File.join(FIXTURE_ROOT, name))
  end

  def parsed_fixture(name)
    JSON.parse(fixture(name))
  end
end
