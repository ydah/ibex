# frozen_string_literal: true

require_relative "../test_helper"

class IRValidatorTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("../fixtures/ir", __dir__)

  def test_validates_and_loads_grammar_fixture
    value = Ibex::IR::Validator.validate(fixture("grammar-v1.json"))

    assert_instance_of Ibex::IR::Grammar, value
    assert_equal "GoldenFixtureParser", value.class_name
  end

  def test_validates_and_loads_automaton_fixture
    value = Ibex::IR::Validator.validate(fixture("automaton-v1.json"))

    assert_instance_of Ibex::IR::Automaton, value
    assert_equal "lalr1", value.algorithm
  end

  def test_accepts_legacy_expansion_origin_without_expression
    source = fixture("grammar-v1-legacy-expansion-origin.json")
    value = Ibex::IR::Validator.validate(source)

    assert_instance_of Ibex::IR::Grammar, value
    assert_equal "optional_expansion", value.productions.first.origin.fetch(:kind)
    refute value.productions.first.origin.key?(:expression)
    assert_equal JSON.parse(source), JSON.parse(Ibex::IR::Serialize.dump(value))
  end

  def test_accepts_optional_symbol_metadata
    document = parsed_fixture("grammar-v1.json")
    document.fetch("symbols").fetch(2)["display_name"] = "number"
    document.fetch("symbols").fetch(2)["semantic_type"] = "Integer"
    document.fetch("symbols").fetch(3)["display_name"] = nil

    value = Ibex::IR::Validator.validate(JSON.generate(document))

    assert_equal "number", value.symbol("NUMBER").display_name
    assert_equal "Integer", value.symbol("NUMBER").semantic_type
    assert_nil value.symbol("PLUS").display_name
  end

  def test_rejects_invalid_json_with_a_position
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate("{") }

    assert_match(/\A\(ir\):1:1: invalid JSON:/, error.message)
  end

  def test_rejects_non_object_root_without_leaking_type_errors
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate("[]") }

    assert_equal "(ir):1:1: $ must be an object", error.message
  end

  def test_rejects_invalid_field_types_with_a_position
    document = parsed_fixture("grammar-v1.json")
    document["symbols"] = "not an array"

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.symbols must be an array", error.message
  end

  def test_rejects_missing_symbol_reference
    document = parsed_fixture("grammar-v1.json")
    document.fetch("productions").fetch(0).fetch("rhs")[0] = 99

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.productions[0].rhs[0] references missing symbol id 99", error.message
  end

  def test_rejects_missing_state_reference
    document = parsed_fixture("automaton-v1.json")
    document.fetch("states").fetch(0).fetch("transitions")["NUMBER"] = 99

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.states[0].transitions.NUMBER references missing state id 99", error.message
  end

  def test_rejects_missing_lookahead_symbol_reference
    document = parsed_fixture("automaton-v1.json")
    document.fetch("states").fetch(0).fetch("items").fetch(0).fetch("lookaheads")[0] = "MISSING"

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal(
      "(ir):1:1: $.states[0].items[0].lookaheads[0] references missing symbol \"MISSING\"",
      error.message
    )
  end

  def test_rejects_an_automaton_without_states
    document = parsed_fixture("automaton-v1.json")
    document["states"] = []

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.states must contain at least one state", error.message
  end

  def test_rejects_a_digest_that_does_not_match_the_embedded_grammar
    document = parsed_fixture("automaton-v1.json")
    document.fetch("grammar")["class_name"] = "ChangedParser"

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_match(
      /\A\(ir\):1:1: \$\.grammar_digest does not match the embedded grammar; expected "sha256:[0-9a-f]{64}"\z/,
      error.message
    )
  end

  def test_rejects_invalid_reduce_reduce_conflict_reductions
    too_short = automaton_with_reduce_reduce_conflict(reductions: [0], chose: 0)
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(too_short)) }
    assert_equal "(ir):1:1: $.states[0].conflicts[0].reductions must contain at least two productions", error.message

    duplicate = automaton_with_reduce_reduce_conflict(reductions: [0, 0], chose: 0)
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(duplicate)) }
    assert_equal "(ir):1:1: $.states[0].conflicts[0].reductions must contain unique production ids", error.message

    missing_choice = automaton_with_reduce_reduce_conflict(reductions: [0, 1], chose: 2)
    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(missing_choice)) }
    assert_equal "(ir):1:1: $.states[0].conflicts[0].resolution.chose must be one of the reductions", error.message
  end

  def test_rejects_inconsistent_conflict_summary
    document = parsed_fixture("automaton-v1.json")
    document.fetch("conflict_summary")["rr"] = 1

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal "(ir):1:1: $.conflict_summary.rr must equal the 0 recorded reduce/reduce conflicts", error.message
  end

  def test_rejects_named_reference_outside_the_action_context
    document = parsed_fixture("grammar-v1.json")
    action = document.fetch("productions").fetch(1).fetch("action")
    action.fetch("named_refs") << { "name" => "outside", "index" => 99 }

    error = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }

    assert_equal(
      "(ir):1:1: $.productions[1].action.named_refs[0].index must be less than the action context length 3",
      error.message
    )
  end

  def test_rejects_missing_discriminator_and_unsupported_version
    missing = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate("{}") }
    assert_equal "(ir):1:1: missing ibex_ir discriminator", missing.message

    document = parsed_fixture("grammar-v1.json")
    document["schema_version"] = 99
    unsupported = assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
    assert_equal "(ir):1:1: unsupported schema_version 99; expected 1", unsupported.message
  end

  private

  def fixture(name)
    File.read(File.join(FIXTURE_ROOT, name))
  end

  def parsed_fixture(name)
    JSON.parse(fixture(name))
  end

  def automaton_with_reduce_reduce_conflict(reductions:, chose:)
    document = parsed_fixture("automaton-v1.json")
    document.fetch("states").fetch(0).fetch("conflicts") << {
      "type" => "reduce_reduce",
      "symbol" => "NUMBER",
      "reductions" => reductions,
      "resolution" => { "by" => "definition_order", "chose" => chose }
    }
    document.fetch("conflict_summary")["rr"] = 1
    document
  end
end
