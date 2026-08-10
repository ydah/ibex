# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"
require_relative "../support/public_json_schemas"

class IRJSONSchemaTest < Minitest::Test
  SCHEMA_ROOT = File.expand_path("../../schema", __dir__)
  FIXTURE_ROOT = File.expand_path("../fixtures/ir", __dir__)
  DRAFT_2020_12 = "https://json-schema.org/draft/2020-12/schema"

  def test_public_schemas_are_valid_json_schema_documents
    Ibex::TestSupport::PublicJSONSchemas::NAMES.each do |name|
      schema = load_json(File.join(SCHEMA_ROOT, name))

      assert_equal DRAFT_2020_12, schema.fetch("$schema")
      assert_match(%r{\Ahttps://raw\.githubusercontent\.com/ydah/ibex/main/schema/}, schema.fetch("$id"))
      assert_equal false, schema.fetch("additionalProperties")
      assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
    end
  end

  def test_current_grammar_schema_accepts_the_current_golden_document
    schemer = JSONSchemer.schema(current_grammar_schema, ref_resolver: public_schema_resolver)

    assert_empty schemer.validate(fixture("grammar.json")).to_a
  end

  def test_current_automaton_schema_accepts_the_current_golden_document
    schemer = JSONSchemer.schema(current_automaton_schema, ref_resolver: public_schema_resolver)

    assert_empty schemer.validate(fixture("automaton.json")).to_a
  end

  def test_current_schema_rejects_removed_compatibility_fields
    document = fixture("grammar.json")
    document["migration"] = nil

    errors = JSONSchemer.schema(current_grammar_schema, ref_resolver: public_schema_resolver).validate(document).to_a
    refute_empty errors
  end

  def test_current_schema_distinguishes_unspecified_from_builtin_default
    document = fixture("grammar.json")
    document.dig("parser_contract", "algorithm").update("value" => "lalr", "explicit" => false, "loc" => nil)

    errors = JSONSchemer.schema(current_grammar_schema, ref_resolver: public_schema_resolver).validate(document).to_a
    refute_empty errors
  end

  def test_current_schema_rejects_unknown_entry_construction
    document = fixture("automaton.json")
    document["entry_construction"] = "unknown"

    errors = JSONSchemer.schema(current_automaton_schema, ref_resolver: public_schema_resolver).validate(document).to_a
    refute_empty errors
  end

  private

  def current_grammar_schema
    @current_grammar_schema ||= load_json(File.join(SCHEMA_ROOT, "grammar-ir.schema.json"))
  end

  def current_automaton_schema
    @current_automaton_schema ||= load_json(File.join(SCHEMA_ROOT, "automaton-ir.schema.json"))
  end

  def public_schema_resolver
    documents = Ibex::TestSupport::PublicJSONSchemas::NAMES.map do |name|
      load_json(File.join(SCHEMA_ROOT, name))
    end
    by_id = documents.to_h { |document| [document.fetch("$id"), document] }
    ->(uri) { by_id[uri.to_s] }
  end

  def fixture(name)
    load_json(File.join(FIXTURE_ROOT, name))
  end

  def load_json(path)
    JSON.parse(File.read(path))
  end
end
