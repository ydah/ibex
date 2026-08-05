# frozen_string_literal: true

require_relative "test_helper"
require "ibex/table_artifact"

class TableArtifactValidationTest < Minitest::Test
  def test_nullable_grammar_accepts_empty_input_in_each_representation
    grammar = <<~GRAMMAR
      class NullableParser
      token ITEM
      rule
      start:
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(grammar, file: "nullable-table-artifact.y").parse
    automaton = Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build

    %i[plain compact].each do |representation|
      document = Ibex::TableArtifact.build(automaton, representation: representation)
      assert_predicate Ibex::TableArtifact::Executor.new(document).recognize([]), :accepted?
    end
  end

  def test_validator_rejects_accept_before_eof_and_eof_shift
    non_eof_accept = fixture_document
    non_eof_accept.dig("payload", "tables", "actions", "codes")[2] = 0
    resign!(non_eof_accept)
    error = assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact::Document.new(non_eof_accept)
    end
    assert_includes error.message, "accept is only valid for $eof"

    eof_shift = fixture_document
    eof_shift.dig("payload", "tables", "actions", "codes")[0] = 2
    resign!(eof_shift)
    error = assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact::Document.new(eof_shift)
    end
    assert_includes error.message, "$eof cannot be shifted"
  end

  def test_validator_rejects_noncanonical_default_and_displacement_actions
    default_accept = fixture_document
    default_accept.dig("payload", "tables", "default_actions")[0] = 0
    resign!(default_accept)
    error = assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact::Document.new(default_accept)
    end
    assert_includes error.message, "must be an error or reduction"

    padded = fixture_document
    padded.dig("payload", "tables", "actions", "codes") << nil
    padded.dig("payload", "tables", "actions", "checks") << nil
    resign!(padded)
    error = assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact::Document.new(padded)
    end
    assert_includes error.message, "canonical minimal row-displacement layout"
  end

  def test_validator_recomputes_representation_cost_claims
    %w[lookup_cost recognition_cost].each do |field|
      changed = fixture_document
      changed.fetch("cost")[field] = "arbitrary"

      error = assert_raises(Ibex::TableArtifact::ValidationError) do
        Ibex::TableArtifact::Document.new(changed)
      end
      assert_includes error.message, "does not match table representation"
    end
  end

  def test_loader_collects_short_reader_chunks_up_to_eof
    reader = Class.new do
      def initialize(value)
        @chunks = value.bytes.each_slice(7).map { |bytes| bytes.pack("C*") }
      end

      def read(_length)
        @chunks.shift
      end
    end.new(fixture_dump)

    assert_equal fixture_dump, Ibex::TableArtifact.load(reader).dump
  end

  private

  def resign!(document)
    payload = document.fetch("payload")
    document.fetch("identity")["payload_digest"] = Ibex::TableArtifact::Serializer.digest(payload)
    document.fetch("cost")["canonical_payload_bytes"] = Ibex::TableArtifact::Serializer.compact(payload).bytesize
  end

  def fixture_document
    JSON.parse(fixture_dump)
  end

  def fixture_dump
    File.read(File.expand_path("fixtures/table_artifact/compact-v1.json", __dir__))
  end
end
