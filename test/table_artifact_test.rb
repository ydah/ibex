# frozen_string_literal: true

require_relative "test_helper"
require "ibex/table_artifact"
require "stringio"

class TableArtifactTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class DataOnlyParser
    pragma extended
    pragma cst
    token NUM PLUS SEMI
    %recover sync: SEMI
    %on_error_reduce expression
    rule
    start: expression @node Root(value)
    expression: NUM @node Number(value)
              | PLUS { raise "semantic action must stay opaque" }
    end
  GRAMMAR

  def test_compact_and_plain_documents_are_executable_table_authorities
    compact = artifact(:compact)
    plain = artifact(:plain)

    [compact, plain].each do |document|
      executor = Ibex::TableArtifact::Executor.new(document)
      accepted = executor.recognize([token_id(document, "NUM")])
      rejected = executor.recognize([token_id(document, "SEMI")])

      assert_predicate accepted, :accepted?
      assert_predicate rejected, :rejected?
    end
    assert_equal "compact", compact.payload.dig("table_format", "representation")
    assert_equal "plain", plain.payload.dig("table_format", "representation")
  end

  def test_round_trip_is_canonical_and_deeply_immutable
    document = artifact(:compact)
    loaded = Ibex::TableArtifact.load(StringIO.new(document.dump))

    assert_equal document.dump, loaded.dump
    assert_predicate loaded.data, :frozen?
    assert_predicate loaded.payload.fetch("tables").fetch("actions").fetch("codes"), :frozen?
    assert_raises(FrozenError) { loaded.payload.fetch("tokens") << {} }
  end

  def test_payload_carries_identity_execution_and_static_metadata
    document = artifact(:compact)
    payload = document.payload

    assert_match(/\Asha256:/, document.identity.fetch("grammar_digest"))
    assert_match(/\Asha256:/, document.identity.fetch("automaton_digest"))
    assert_equal 6, payload.dig("table_format", "version")
    assert_equal(["$eof", "error", "NUM", "PLUS", "SEMI"], payload.fetch("tokens").map { |token| token.fetch("name") })
    assert_equal [{ "name" => "start", "state" => 0 }], payload.fetch("entry_states")
    assert_equal [4], payload.dig("recovery", "sync_token_ids")
    assert_equal [[6]], payload.dig("recovery", "on_error_reduce_symbol_ids")
    assert_equal "Root", payload.dig("cst", "slots", 0, "node_name")
    assert_equal false, payload.dig("semantic_actions", "verified")
    assert_operator document.cost.fetch("canonical_payload_bytes"), :>, 0
    assert_equal true, document.cost.fetch("bounded_by_max_steps")
    assert_equal "not-measured", document.cost.fetch("measurement")
  end

  def test_semantic_action_source_is_neither_serialized_nor_executed
    document = artifact(:compact)

    refute_includes document.dump, "semantic action must stay opaque"
    assert_equal "opaque-wrapper-production-id-v1", document.payload.dig("semantic_actions", "binding")
    assert_predicate Ibex::TableArtifact::Executor.new(document).recognize([token_id(document, "NUM")]), :accepted?
  end

  def test_payload_tampering_is_rejected_before_execution
    tampered = JSON.parse(artifact(:compact).dump)
    tampered.dig("payload", "tables", "actions", "codes").map!.with_index do |code, index|
      index.zero? ? 999_999 : code
    end

    error = assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact.load(JSON.generate(tampered))
    end
    assert_includes error.message, "payload_digest"
  end

  def test_re_signed_referential_tampering_is_rejected
    tampered = JSON.parse(artifact(:compact).dump)
    production = tampered.dig("payload", "productions", 0)
    production["rhs_length"] += 1
    resign!(tampered)

    error = assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact.load(JSON.generate(tampered))
    end
    assert_includes error.message, "rhs_length"
  end

  def test_named_metadata_digests_reject_independently_re_signed_tampering
    mutations = {
      "cst_metadata_digest" => ->(document) { document.dig("payload", "cst", "slots", 0)["node_name"] = "Changed" },
      "recovery_metadata_digest" => ->(document) { document.dig("payload", "recovery", "sync_token_ids").replace([2]) }
    }

    mutations.each do |digest_name, mutate|
      tampered = JSON.parse(artifact(:compact).dump)
      mutate.call(tampered)
      resign!(tampered)

      error = assert_raises(Ibex::TableArtifact::ValidationError) do
        Ibex::TableArtifact.load(JSON.generate(tampered))
      end
      assert_includes error.message, digest_name
    end
  end

  def test_closed_loader_rejects_unknown_fields_and_oversized_input
    tampered = JSON.parse(artifact(:compact).dump)
    tampered["generated_ruby"] = "raise"

    error = assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact.load(JSON.generate(tampered))
    end
    assert_includes error.message, "unknown fields"
    assert_raises(Ibex::TableArtifact::ValidationError) do
      Ibex::TableArtifact.load(artifact(:compact).dump, max_bytes: 8)
    end
  end

  def test_executor_requires_internal_token_ids_and_obeys_step_bound
    executor = Ibex::TableArtifact::Executor.new(artifact(:compact))

    assert_raises(ArgumentError) { executor.recognize([999]) }
    assert_raises(ArgumentError) { executor.recognize([0, 2]) }
    assert_predicate executor.recognize([2], max_steps: 1), :exhausted?
  end

  def test_sidecar_construction_does_not_change_generated_ruby_bytes
    before = Ibex::Codegen::Ruby.new(automaton).generate

    artifact(:compact)
    after = Ibex::Codegen::Ruby.new(automaton).generate

    assert_equal before, after
  end

  def test_canonical_fixture_is_stable
    expected = File.read(File.expand_path("fixtures/table_artifact/compact-v1.json", __dir__))

    assert_equal expected, artifact(:compact).dump
  end

  private

  def artifact(representation)
    @artifacts ||= {}
    @artifacts[representation] ||= Ibex::TableArtifact.build(automaton, representation: representation)
  end

  def automaton
    @automaton ||= begin
      ast = Ibex::Frontend::Parser.new(SOURCE, file: "table_artifact.y").parse
      Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
    end
  end

  def token_id(document, name)
    document.payload.fetch("tokens").find { |token| token.fetch("name") == name }.fetch("id")
  end

  def resign!(document)
    payload = document.fetch("payload")
    document.fetch("identity")["payload_digest"] = Ibex::TableArtifact::Serializer.digest(payload)
    document.fetch("cost")["canonical_payload_bytes"] = Ibex::TableArtifact::Serializer.compact(payload).bytesize
  end
end
