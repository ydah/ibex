# frozen_string_literal: true

require_relative "test_helper"
require "ibex/verifiable_generation_bundle"
require "json_schemer"
require "tmpdir"

class VerificationReportSchemaTest < Minitest::Test
  SCHEMA_PATH = File.expand_path("../schema/verification-report-v1.schema.json", __dir__)

  def test_schema_is_closed_and_valid_draft_2020_twelve
    schema = JSON.parse(File.read(SCHEMA_PATH))

    assert_equal "https://json-schema.org/draft/2020-12/schema", schema.fetch("$schema")
    assert_equal false, schema.fetch("additionalProperties")
    assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
  end

  def test_schema_accepts_default_strict_and_exhausted_reports
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))

    Dir.mktmpdir("ibex-verification-schema") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      input = Ibex::GenerationInput.new(path, source)
      table = Ibex::TableArtifact.build(automaton)
      [{}, { strict: true }, { max_states: 1 }].each do |options|
        report = Ibex::VerificationReport.render(
          automaton, table: table, source_records: [input], table_path: "parser.tables.ibex.json", **options
        )
        assert_empty schemer.validate(JSON.parse(report)).to_a
      end
    end
  end

  def test_schema_rejects_open_records_and_hidden_manifest_binding
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    document = report_document
    document["manifest_digest"] = "sha256:#{'0' * 64}"

    refute_empty schemer.validate(document).to_a
  end

  private

  def report_document
    Dir.mktmpdir("ibex-verification-schema") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      input = Ibex::GenerationInput.new(path, source)
      table = Ibex::TableArtifact.build(automaton)
      return JSON.parse(
        Ibex::VerificationReport.render(
          automaton, table: table, source_records: [input], table_path: "parser.tables.ibex.json"
        )
      )
    end
  end

  def source
    <<~GRAMMAR
      class VerificationSchemaParser
      token ITEM
      rule
      start: ITEM
      end
    GRAMMAR
  end

  def automaton
    @automaton ||= begin
      ast = Ibex::Frontend::Parser.new(source, file: "grammar.y").parse
      Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
    end
  end
end
