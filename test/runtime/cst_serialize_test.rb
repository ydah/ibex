# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"

class CSTSerializeTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("../fixtures/cst", __dir__)
  SCHEMA_PATH = File.expand_path("../../schema/cst-v1.json", __dir__)
  SOURCE = <<~GRAMMAR
    class SerializedCSTParser
    pragma cst
    token WORD
    lexer
      skip /[[:space:]]+/
      WORD /[a-z]+/
    end
    rule
    start: WORD
    end
  GRAMMAR

  def test_dump_load_dump_is_byte_stable
    documents.each do |name, source|
      write_fixture(name, source) if ENV["UPDATE_IBEX_CST_FIXTURES"] == "1"
      expected = File.binread(File.join(FIXTURE_ROOT, name))
      loaded = Ibex::Runtime::CST::Serialize.load(expected, grammar_digest: grammar_digest)

      assert_equal expected, source
      assert_equal expected, Ibex::Runtime::CST::Serialize.dump(loaded)
      assert_equal loaded.green_root.to_source.bytesize, loaded.green_root.full_width
    end
  end

  def test_non_utf8_text_uses_base64_and_round_trips_bytes
    source = documents.fetch("invalid-utf8-v1.json")
    document = JSON.parse(source)
    token = document.fetch("root").fetch("c").fetch(0).fetch("c").fetch(0)
    loaded = Ibex::Runtime::CST::Serialize.load(source)

    assert_equal({ "b64" => "/w==" }, token.fetch("t"))
    assert_equal "\xFF".b, loaded.syntax_root.first_token.text
    assert_equal source, Ibex::Runtime::CST::Serialize.dump(loaded)
  end

  def test_public_schema_accepts_both_golden_documents
    schema = JSON.parse(File.read(SCHEMA_PATH))
    schemer = JSONSchemer.schema(schema)

    assert_equal "https://json-schema.org/draft/2020-12/schema", schema.fetch("$schema")
    assert_equal false, schema.fetch("additionalProperties")
    assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
    documents.each_value do |source|
      assert_empty schemer.validate(JSON.parse(source)).to_a
    end
  end

  def test_validator_reports_digest_and_kind_failures_structurally
    mismatch = assert_raises(Ibex::Runtime::CST::ValidationError) do
      Ibex::Runtime::CST::Serialize.load(
        documents.fetch("valid-v1.json"),
        grammar_digest: "sha256:#{'0' * 64}"
      )
    end
    document = JSON.parse(documents.fetch("valid-v1.json"))
    document.fetch("root")["k"] = 99_999
    invalid_kind = assert_raises(Ibex::Runtime::CST::ValidationError) do
      Ibex::Runtime::CST::Serialize.load(JSON.generate(document))
    end

    assert_equal :grammar_digest_mismatch, mismatch.code
    assert_equal "$.grammar_digest", mismatch.path
    assert_equal :invalid_kind, invalid_kind.code
    assert_equal "$.root.k", invalid_kind.path
  end

  def test_derived_flags_widths_and_descendant_counts_are_rebuilt
    loaded = Ibex::Runtime::CST::Serialize.load(documents.fetch("valid-v1.json"))
    root = loaded.green_root

    assert root.flags.anybits?(Ibex::Runtime::CST::Flags::SYNTHETIC)
    assert_equal root.to_source.bytesize, root.full_width
    assert_equal 1 + root.children.sum(&:descendant_count), root.descendant_count
    shareable = TestRuntimeCapabilities.ractor_shareable?(root)
    assert shareable unless shareable.nil?
  end

  def test_annotated_trees_are_rejected_instead_of_silently_losing_annotations
    annotation = Ibex::Runtime::CST::SyntaxAnnotation.new
    annotated = syntax_root.annotate(annotation)

    assert_raises(Ibex::Runtime::CST::SerializationError) { dump(annotated) }
  end

  def test_trivia_policy_round_trips_with_coordinate_safety
    root = syntax_root
    dropped = Ibex::Runtime::CST::SyntaxNode.new(
      green: root.green, kinds: root.kinds, trivia_policy: :drop, source_text: root.source_text
    )
    loaded = Ibex::Runtime::CST::Serialize.load(dump(dropped))

    assert_equal :drop, loaded.trivia_policy
    assert_raises(Ibex::Runtime::CST::TriviaDroppedError) { loaded.syntax_root.span }
  end

  def test_parse_memo_round_trips_and_metadata_mismatch_discards_it # rubocop:disable Metrics/AbcSize
    session = parser_class.incremental_session(Ibex::Runtime::CST::SourceText.new("word "))
    source = Ibex::Runtime::CST::Serialize.dump(
      session.result.syntax_root,
      grammar_digest: grammar_digest,
      table_format: parser_tables.fetch(:format_version),
      state_count: parser_tables.fetch(:state_count),
      production_count: parser_tables.fetch(:production_count),
      memo: session.parse_memo
    )
    loaded = Ibex::Runtime::CST::Serialize.load(
      source,
      grammar_digest: grammar_digest,
      state_count: parser_tables.fetch(:state_count),
      production_count: parser_tables.fetch(:production_count)
    )
    schema = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    mismatched = Ibex::Runtime::CST::Serialize.load(
      source,
      grammar_digest: grammar_digest,
      state_count: parser_tables.fetch(:state_count) + 1,
      production_count: parser_tables.fetch(:production_count)
    )

    assert_equal session.parse_memo.left_states, loaded.memo.left_states
    assert_empty schema.validate(JSON.parse(source)).to_a
    assert_equal source, Ibex::Runtime::CST::Serialize.dump(loaded)
    assert_nil mismatched.memo
    assert_equal loaded.green_root, mismatched.green_root
  end

  def test_invalid_parse_memo_length_is_rejected
    document = JSON.parse(dump(syntax_root))
    document["memo"] = { "version" => 1, "left_states" => [0] }

    error = assert_raises(Ibex::Runtime::CST::ValidationError) do
      Ibex::Runtime::CST::Serialize.load(JSON.generate(document))
    end

    assert_equal :invalid_memo_length, error.code
    assert_equal "$.memo.left_states", error.path
  end

  private

  def documents
    @documents ||= {
      "valid-v1.json" => dump(syntax_root),
      "invalid-utf8-v1.json" => dump(syntax_root.first_token.with_text("\xFF".b))
    }.freeze
  end

  def syntax_root
    @syntax_root ||= parser_class.new.parse_with_syntax("word ").syntax_root
  end

  def parser_class
    @parser_class ||= begin
      ast = Ibex::Frontend::Parser.new(SOURCE, file: "serialized.y").parse
      grammar = Ibex::Normalizer.new(ast).normalize
      automaton = Ibex::LALR::Builder.new(grammar).build
      namespace = Module.new
      namespace.module_eval(Ibex::Codegen::Ruby.new(automaton).generate, "serialized_parser.rb")
      namespace.const_get(:SerializedCSTParser)
    end
  end

  def parser_tables = parser_class.parser_tables
  def grammar_digest = parser_tables.fetch(:grammar_digest)

  def dump(root)
    Ibex::Runtime::CST::Serialize.dump(
      root,
      grammar_digest: grammar_digest,
      table_format: parser_tables.fetch(:format_version),
      state_count: parser_tables.fetch(:state_count),
      production_count: parser_tables.fetch(:production_count)
    )
  end

  def write_fixture(name, source)
    File.binwrite(File.join(FIXTURE_ROOT, name), source)
  end
end
