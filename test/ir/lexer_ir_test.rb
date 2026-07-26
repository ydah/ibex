# frozen_string_literal: true

require_relative "../test_helper"
require "json_schemer"

class LexerIRTest < Minitest::Test
  SCHEMA_ROOT = File.expand_path("../../schema", __dir__)

  def test_normalizes_and_round_trips_an_independently_versioned_lexer
    lexer = grammar.lexer
    refute_nil lexer
    assert_equal 1, lexer.schema_version
    assert_equal %w[INITIAL STRING], lexer.states
    assert_equal %i[skip token on token on], lexer.rules.map(&:kind)
    assert_equal %w[INITIAL INITIAL STRING STRING INITIAL], lexer.rules.map(&:state)

    dumped = Ibex::IR::Serialize.dump(lexer)
    loaded = Ibex::IR::Validator.validate(dumped)
    assert_instance_of Ibex::IR::Lexer, loaded
    assert_equal dumped, Ibex::IR::Serialize.dump(loaded)
    assert_empty lexer_schema.validate(JSON.parse(dumped)).to_a
  end

  def test_embeds_the_lexer_without_changing_its_schema_version
    dumped = Ibex::IR::Serialize.dump(grammar)
    document = JSON.parse(dumped)
    loaded = Ibex::IR::Validator.validate(dumped)

    assert_equal 2, document.fetch("schema_version")
    assert_equal 1, document.fetch("lexer").fetch("schema_version")
    assert_equal grammar.lexer.to_h, loaded.lexer.to_h
  end

  def test_enforces_declared_tokens_nonempty_matches_and_flat_states
    sources = [
      lexer_source("MISSING /x/"),
      lexer_source("NUM //"),
      lexer_source("state A do\nstate B do\nNUM /x/\nend\nend"),
      lexer_source("NUM /x/ { |left, right| left }")
    ]
    messages = [
      "undeclared terminal MISSING", "must not match an empty string", "nested lexer states",
      "lexer action accepts exactly one local identifier"
    ]

    sources.zip(messages).each do |source, message|
      error = assert_raises(Ibex::Error) { normalize(source) }
      assert_includes error.message, message
    end
  end

  def test_emits_a_structured_redos_warning
    value = normalize(lexer_source("NUM /(a+)+/"))

    assert_equal :lexer_redos, value.warnings.find { |warning| warning[:type] == :lexer_redos }.fetch(:type)
    assert_equal :redos, value.lexer.warnings.fetch(0).fetch(:type)
  end

  private

  def grammar
    @grammar ||= normalize(File.read(File.expand_path("../fixtures/grammar/lexer.y", __dir__)))
  end

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "lexer.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end

  def lexer_source(rule)
    <<~GRAMMAR
      class P
      pragma extended
      token NUM
      lexer
      #{rule}
      end
      rule
      start: NUM
      end
    GRAMMAR
  end

  def lexer_schema
    JSONSchemer.schema(JSON.parse(File.read(File.join(SCHEMA_ROOT, "lexer-ir-v1.schema.json"))))
  end
end
