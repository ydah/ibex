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

  def test_schema_rejects_noncanonical_and_control_character_logical_paths
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    original = report_document

    invalid_logical_paths.each do |kind, paths|
      paths.each do |path|
        document = Marshal.load(Marshal.dump(original))
        set_logical_path(document, kind, path)
        refute_empty schemer.validate(document).to_a, "#{kind}: #{path.inspect}"
      end
    end
  end

  def test_schema_rejects_excess_inputs
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    original = report_document

    too_many = Marshal.load(Marshal.dump(original))
    entry = too_many.dig("input", "files", 0)
    too_many.fetch("input")["files"] = Array.new(10_001, entry)
    refute_empty schemer.validate(too_many).to_a
  end

  def test_schema_accepts_unicode_logical_basenames
    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    document = report_document
    document.dig("input", "files", 0)["logical_path"] = "input/0000/文法.y"
    document.fetch("table")["logical_path"] = "table/表.ibex.json"

    assert_empty schemer.validate(document).to_a
  end

  private

  def invalid_logical_paths
    {
      input: ["input/0000/subdir/x", "input/0000/", "input/0000/x\n", "input/0000/x\r", "input/0000/x\u0001"],
      table: ["table/subdir/x", "table/", "table/x\n", "table/x\r", "table/x\u0001"]
    }
  end

  def set_logical_path(document, kind, path)
    if kind == :input
      document.dig("input", "files", 0)["logical_path"] = path
    else
      document.fetch("table")["logical_path"] = path
    end
  end

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
