# frozen_string_literal: true

require_relative "test_helper"
require "ibex/table_artifact"
require "json_schemer"

class TableArtifactSchemaTest < Minitest::Test
  SCHEMA_PATH = File.expand_path("../schema/table-artifact-v1.schema.json", __dir__)

  def test_schema_is_closed_and_valid_draft_2020_twelve
    schema = JSON.parse(File.read(SCHEMA_PATH))

    assert_equal "https://json-schema.org/draft/2020-12/schema", schema.fetch("$schema")
    assert_equal false, schema.fetch("additionalProperties")
    assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
  end

  def test_schema_accepts_plain_and_compact_builder_documents
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))

    %i[plain compact].each do |representation|
      document = Ibex::TableArtifact.build(automaton, representation: representation).data
      assert_empty schemer.validate(document).to_a
    end
  end

  def test_schema_rejects_executable_code_and_open_nested_records
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    document = JSON.parse(Ibex::TableArtifact.build(automaton).dump)
    document.dig("payload", "productions", 0)["ruby_action"] = "raise"

    refute_empty schemer.validate(document).to_a
  end

  private

  def automaton
    source = <<~GRAMMAR
      class SchemaParser
      token ITEM
      rule
      start: items
      items: items ITEM |
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "table_artifact_schema.y").parse
    Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
  end
end
