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
      canonical = Ibex::VerificationReport.canonical_automaton(automaton, source_records: [input])
      table = Ibex::TableArtifact.build(canonical)
      [{}, { strict: true }, { max_states: 1 }].each do |options|
        report = Ibex::VerificationReport.render(
          canonical, table: table, source_records: [input], table_path: "parser.tables.ibex.json", **options
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

    document = report_document
    document.fetch("ir")["identity_scope"] = "raw-source-path-v1"
    refute_empty schemer.validate(document).to_a
  end

  def test_schema_rejects_noncanonical_logical_paths_and_excess_inputs
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    original = report_document
    mutations = [
      ->(value) { value.dig("input", "files", 0)["logical_path"] = "input/0000/subdir/x" },
      ->(value) { value.dig("input", "files", 0)["logical_path"] = "input/0000/" },
      ->(value) { value.fetch("table")["logical_path"] = "table/subdir/x" },
      ->(value) { value.fetch("table")["logical_path"] = "table/" }
    ]

    mutations.each do |mutate|
      document = Marshal.load(Marshal.dump(original))
      mutate.call(document)
      refute_empty schemer.validate(document).to_a
    end

    too_many = Marshal.load(Marshal.dump(original))
    entry = too_many.dig("input", "files", 0)
    too_many.fetch("input")["files"] = Array.new(10_001, entry)
    refute_empty schemer.validate(too_many).to_a
  end

  private

  def report_document
    Dir.mktmpdir("ibex-verification-schema") do |directory|
      path = File.join(directory, "grammar.y")
      File.binwrite(path, source)
      input = Ibex::GenerationInput.new(path, source)
      canonical = Ibex::VerificationReport.canonical_automaton(automaton, source_records: [input])
      table = Ibex::TableArtifact.build(canonical)
      return JSON.parse(
        Ibex::VerificationReport.render(
          canonical, table: table, source_records: [input], table_path: "parser.tables.ibex.json"
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
