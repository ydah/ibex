# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"

class IRJSONSchemaTest < Minitest::Test
  SCHEMA_ROOT = File.expand_path("../../schema", __dir__)
  FIXTURE_ROOT = File.expand_path("../fixtures/ir", __dir__)
  DRAFT_2020_12 = "https://json-schema.org/draft/2020-12/schema"

  def test_public_schemas_are_valid_json_schema_2020_12_documents
    %w[grammar-ir-v1.schema.json automaton-ir-v1.schema.json].each do |name|
      schema = load_json(File.join(SCHEMA_ROOT, name))

      assert_equal DRAFT_2020_12, schema.fetch("$schema")
      assert_match(%r{\Ahttps://raw\.githubusercontent\.com/ydah/ibex/main/schema/}, schema.fetch("$id"))
      assert_equal false, schema.fetch("additionalProperties")
      assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
    end
  end

  def test_grammar_schema_documents_additive_v1_fields
    schema = grammar_schema
    symbol = schema.dig("$defs", "symbol")

    assert symbol.fetch("properties").key?("display_name")
    assert symbol.fetch("properties").key?("semantic_type")
    refute_includes symbol.fetch("required"), "display_name"
    refute_includes symbol.fetch("required"), "semantic_type"
    refute_includes schema.fetch("required"), "user_code_chunks"
  end

  def test_automaton_schema_embeds_the_grammar_v1_contract
    assert_equal "grammar-ir-v1.schema.json", automaton_schema.dig("properties", "grammar", "$ref")
  end

  def test_grammar_schema_accepts_golden_and_legacy_v1_documents
    schemer = JSONSchemer.schema(grammar_schema)

    assert_empty schemer.validate(fixture("grammar-v1.json")).to_a
    assert_empty schemer.validate(fixture("grammar-v1-legacy-expansion-origin.json")).to_a
  end

  def test_metadata_control_character_rejection_matches_the_runtime_validator
    document = fixture("grammar-v1.json")
    document.fetch("symbols").fetch(2)["display_name"] = "number\u0085alias"

    refute_empty JSONSchemer.schema(grammar_schema).validate(document).to_a
    assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
  end

  def test_automaton_schema_accepts_the_golden_v1_document_and_resolves_the_grammar_schema
    resolver = lambda do |uri|
      grammar_schema if uri.to_s == grammar_schema.fetch("$id")
    end
    schemer = JSONSchemer.schema(automaton_schema, ref_resolver: resolver)

    assert_empty schemer.validate(fixture("automaton-v1.json")).to_a
  end

  private

  def grammar_schema
    @grammar_schema ||= load_json(File.join(SCHEMA_ROOT, "grammar-ir-v1.schema.json"))
  end

  def automaton_schema
    @automaton_schema ||= load_json(File.join(SCHEMA_ROOT, "automaton-ir-v1.schema.json"))
  end

  def fixture(name)
    load_json(File.join(FIXTURE_ROOT, name))
  end

  def load_json(path)
    JSON.parse(File.read(path))
  end
end
