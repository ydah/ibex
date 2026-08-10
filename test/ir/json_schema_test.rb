# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"
require_relative "../support/public_json_schemas"

class IRJSONSchemaTest < Minitest::Test # rubocop:disable Metrics/ClassLength -- one public schema family.
  SCHEMA_ROOT = File.expand_path("../../schema", __dir__)
  FIXTURE_ROOT = File.expand_path("../fixtures/ir", __dir__)
  DRAFT_2020_12 = "https://json-schema.org/draft/2020-12/schema"

  def test_public_schemas_are_valid_json_schema_2020_12_documents
    Ibex::TestSupport::PublicJSONSchemas::NAMES.each do |name|
      schema = load_json(File.join(SCHEMA_ROOT, name))

      assert_equal DRAFT_2020_12, schema.fetch("$schema")
      assert_match(%r{\Ahttps://raw\.githubusercontent\.com/ydah/ibex/main/schema/}, schema.fetch("$id"))
      assert_equal false, schema.fetch("additionalProperties")
      assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
    end
  end

  def test_grammar_schema_documents_additive_v2_fields
    schema = current_grammar_schema
    symbol = schema.dig("$defs", "symbol")

    assert symbol.fetch("properties").key?("display_name")
    assert symbol.fetch("properties").key?("semantic_type")
    refute_includes symbol.fetch("required"), "display_name"
    refute_includes symbol.fetch("required"), "semantic_type"
    refute_includes schema.fetch("required"), "user_code_chunks"
  end

  def test_automaton_schema_embeds_the_grammar_v2_contract
    assert_equal "grammar-ir-v2.schema.json", current_automaton_schema.dig("properties", "grammar", "$ref")
  end

  def test_grammar_schema_accepts_the_current_golden_document
    schemer = JSONSchemer.schema(current_grammar_schema, ref_resolver: public_schema_resolver)

    assert_empty schemer.validate(fixture("grammar-v2.json")).to_a
  end

  def test_metadata_control_character_rejection_matches_the_runtime_validator
    document = fixture("grammar-v2.json")
    document.fetch("symbols").fetch(2)["display_name"] = "number\u0085alias"

    refute_empty JSONSchemer.schema(current_grammar_schema, ref_resolver: public_schema_resolver).validate(document).to_a
    assert_raises(Ibex::Error) { Ibex::IR::Validator.validate(JSON.generate(document)) }
  end

  def test_automaton_schema_accepts_the_current_golden_document_and_resolves_the_grammar_schema
    resolver = lambda do |uri|
      current_grammar_schema if uri.to_s == current_grammar_schema.fetch("$id")
    end
    schemer = JSONSchemer.schema(current_automaton_schema, ref_resolver: public_schema_resolver)

    assert_empty schemer.validate(fixture("automaton-v2.json")).to_a
  end

  def test_v2_schemas_accept_default_and_migrated_golden_documents
    grammar = schema("grammar-ir-v2.schema.json")
    automaton = schema("automaton-ir-v2.schema.json")
    resolver = lambda do |uri|
      {
        grammar_schema.fetch("$id") => grammar_schema,
        automaton_schema.fetch("$id") => automaton_schema,
        grammar.fetch("$id") => grammar,
        automaton.fetch("$id") => automaton
      }[uri.to_s]
    end

    grammar_schemer = JSONSchemer.schema(grammar, ref_resolver: resolver)
    assert_empty grammar_schemer.validate(fixture("grammar-v2.json")).to_a
    automaton_schemer = JSONSchemer.schema(automaton, ref_resolver: resolver)
    assert_empty automaton_schemer.validate(fixture("automaton-v2.json")).to_a
  end

  def test_v3_schemas_accept_native_and_migrated_golden_documents
    grammar = schema("grammar-ir-v3.schema.json")
    automaton = schema("automaton-ir-v3.schema.json")
    resolver = public_schema_resolver(grammar, automaton)

    grammar_schemer = JSONSchemer.schema(grammar, ref_resolver: resolver)
    assert_empty grammar_schemer.validate(fixture("grammar-v3.json")).to_a
    assert_empty grammar_schemer.validate(fixture("grammar-v2-migrated-v3.json")).to_a

    automaton_schemer = JSONSchemer.schema(automaton, ref_resolver: resolver)
    assert_empty automaton_schemer.validate(fixture("automaton-v3.json")).to_a
    assert_empty automaton_schemer.validate(fixture("automaton-v2-migrated-v3.json")).to_a
  end

  def test_v3_schema_distinguishes_unspecified_from_builtin_default
    grammar = schema("grammar-ir-v3.schema.json")
    document = fixture("grammar-v2-migrated-v3.json")
    document.dig("parser_contract", "algorithm")["value"] = "lalr"

    refute_empty JSONSchemer.schema(grammar, ref_resolver: public_schema_resolver(grammar)).validate(document).to_a
  end

  def test_v2_grammar_schema_accepts_constructor_parameters
    grammar = schema("grammar-ir-v2.schema.json")
    resolver = ->(uri) { grammar_schema if uri.to_s == grammar_schema.fetch("$id") }
    document = fixture("grammar-v2.json")
    document["params"] = [{ "name" => "context", "semantic_type" => "Object" }]

    assert_empty JSONSchemer.schema(grammar, ref_resolver: resolver).validate(document).to_a
  end

  def test_v2_grammar_schema_accepts_known_grammar_modes
    grammar = schema("grammar-ir-v2.schema.json")
    resolver = ->(uri) { grammar_schema if uri.to_s == grammar_schema.fetch("$id") }
    schemer = JSONSchemer.schema(grammar, ref_resolver: resolver)
    document = fixture("grammar-v2.json")

    %w[default extended].each do |mode|
      document["mode"] = mode
      assert_empty schemer.validate(document).to_a
    end

    document["mode"] = "future"
    refute_empty schemer.validate(document).to_a
  end

  def test_cst_option_is_additive_only_in_the_v2_schema
    grammar = schema("grammar-ir-v2.schema.json")
    resolver = ->(uri) { grammar_schema if uri.to_s == grammar_schema.fetch("$id") }
    document = fixture("grammar-v2.json")
    document["mode"] = "extended"
    document.fetch("options")["cst"] = true

    assert_empty JSONSchemer.schema(grammar, ref_resolver: resolver).validate(document).to_a

  end

  def test_v2_grammar_schema_accepts_ast_node_metadata
    grammar = schema("grammar-ir-v2.schema.json")
    resolver = ->(uri) { grammar_schema if uri.to_s == grammar_schema.fetch("$id") }
    document = fixture("grammar-v2.json")
    document.fetch("productions").fetch(0)["node"] = {
      "name" => "Root",
      "fields" => ["value"],
      "loc" => { "file" => "grammar.y", "line" => 10, "column" => 18 }
    }

    assert_empty JSONSchemer.schema(grammar, ref_resolver: resolver).validate(document).to_a
    assert Ibex::IR::Validator.validate(JSON.generate(document)).productions.fetch(0).node
  end

  def test_v2_schemas_accept_multiple_starts_and_entry_states
    grammar = schema("grammar-ir-v2.schema.json")
    automaton = schema("automaton-ir-v2.schema.json")
    resolver = lambda do |uri|
      {
        grammar_schema.fetch("$id") => grammar_schema,
        automaton_schema.fetch("$id") => automaton_schema,
        grammar.fetch("$id") => grammar
      }[uri.to_s]
    end
    document = fixture("automaton-v2.json")
    document.fetch("grammar")["mode"] = "extended"
    document.fetch("grammar")["starts"] = %w[start expression]
    document["entry_states"] = { "start" => 0, "expression" => 1 }

    assert_empty JSONSchemer.schema(automaton, ref_resolver: resolver).validate(document).to_a
  end

  def test_v2_grammar_schema_accepts_value_printers
    grammar = schema("grammar-ir-v2.schema.json")
    resolver = ->(uri) { grammar_schema if uri.to_s == grammar_schema.fetch("$id") }
    document = fixture("grammar-v2.json")
    document["printers"] = [
      {
        "symbol" => "NUMBER",
        "code" => "value.to_s",
        "loc" => { "file" => "grammar.y", "line" => 2, "column" => 1 }
      }
    ]

    assert_empty JSONSchemer.schema(grammar, ref_resolver: resolver).validate(document).to_a
  end

  def test_v2_grammar_schema_accepts_recovery_policy
    grammar = schema("grammar-ir-v2.schema.json")
    resolver = ->(uri) { grammar_schema if uri.to_s == grammar_schema.fetch("$id") }
    document = fixture("grammar-v2.json")
    document["mode"] = "extended"
    document["recovery"] = {
      "sync_tokens" => ["PLUS"],
      "on_error_reduce" => [["expression"]]
    }

    assert_empty JSONSchemer.schema(grammar, ref_resolver: resolver).validate(document).to_a
  end

  def test_v2_grammar_schema_accepts_grammar_tests
    grammar = schema("grammar-ir-v2.schema.json")
    resolver = ->(uri) { grammar_schema if uri.to_s == grammar_schema.fetch("$id") }
    document = fixture("grammar-v2.json")
    document["mode"] = "extended"
    document["tests"] = [
      {
        "expectation" => "accept",
        "source" => "ok",
        "loc" => { "file" => "grammar.y", "line" => 3, "column" => 1 }
      }
    ]

    assert_empty JSONSchemer.schema(grammar, ref_resolver: resolver).validate(document).to_a
  end

  def test_error_ux_snapshot_matches_its_public_schema
    contract = schema("error-ux-v1.schema.json")
    document = load_json(File.join(FIXTURE_ROOT, "../error_ux/json-errors-v1.json"))

    assert_empty JSONSchemer.schema(contract).validate(document).to_a
  end

  private

  def grammar_schema
    @grammar_schema ||= load_json(File.join(SCHEMA_ROOT, "grammar-ir-v1.schema.json"))
  end

  def automaton_schema
    @automaton_schema ||= load_json(File.join(SCHEMA_ROOT, "automaton-ir-v1.schema.json"))
  end

  def current_grammar_schema
    @current_grammar_schema ||= load_json(File.join(SCHEMA_ROOT, "grammar-ir-v2.schema.json"))
  end

  def current_automaton_schema
    @current_automaton_schema ||= load_json(File.join(SCHEMA_ROOT, "automaton-ir-v2.schema.json"))
  end

  def schema(name)
    load_json(File.join(SCHEMA_ROOT, name))
  end

  def public_schema_resolver(*additional)
    documents = [
      grammar_schema,
      automaton_schema,
      current_grammar_schema,
      current_automaton_schema,
      schema("grammar-ir-v2.schema.json"),
      schema("automaton-ir-v2.schema.json"),
      schema("lexer-ir-v1.schema.json"),
      *additional
    ]
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
