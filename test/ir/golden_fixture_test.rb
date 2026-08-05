# frozen_string_literal: true

require_relative "../test_helper"

class GoldenFixtureTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("../fixtures/ir", __dir__)
  REFRESH_VARIABLE = "UPDATE_IBEX_IR_FIXTURES"
  SOURCE = <<~GRAMMAR
    class GoldenFixtureParser
    token NUMBER PLUS
    preclow
    left PLUS
    prechigh
    convert
    NUMBER 'Integer'
    end
    rule
    start: expression
    expression: expression PLUS NUMBER { result = val[0] + val[2] }
              | NUMBER
    end
    ---- inner
    def fixture_helper = true
  GRAMMAR

  def test_grammar_ir_schema_v2_golden_fixture
    grammar, = build_pipeline
    assert_golden("grammar-v2.json", grammar, version: 2)
  end

  def test_automaton_ir_schema_v2_golden_fixture
    _, automaton = build_pipeline
    assert_golden("automaton-v2.json", automaton, version: 2)
  end

  def test_grammar_ir_schema_v3_parser_contract_golden_fixture
    grammar, = build_v3_pipeline
    assert_golden("grammar-v3.json", grammar, version: 3)
  end

  def test_automaton_ir_schema_v3_parser_contract_golden_fixture
    _, automaton = build_v3_pipeline
    assert_golden("automaton-v3.json", automaton, version: 3)
  end

  def test_schema_v1_golden_fixtures_remain_byte_stable
    %w[grammar-v1.json automaton-v1.json].each do |name|
      expected = File.read(File.join(FIXTURE_ROOT, name))
      loaded = Ibex::IR::Serialize.load(expected)

      assert_equal 1, loaded.schema_version
      assert_equal expected, Ibex::IR::Serialize.dump(loaded), "#{name} must remain byte-stable"
    end
  end

  def test_schema_v1_to_v2_migration_golden_fixtures
    %w[grammar automaton].each do |kind|
      source = File.read(File.join(FIXTURE_ROOT, "#{kind}-v1.json"))
      migrated = Ibex::IR::Migration.to_v2(Ibex::IR::Validator.validate(source))

      assert_golden("#{kind}-v1-migrated-v2.json", migrated, version: 2)
      assert_same migrated, Ibex::IR::Migration.to_v2(migrated)
    end
  end

  def test_schema_v2_to_v3_migration_golden_fixtures
    %w[grammar automaton].each do |kind|
      source = File.read(File.join(FIXTURE_ROOT, "#{kind}-v2.json"))
      migrated = Ibex::IR::Migration.to_v3(Ibex::IR::Validator.validate(source))

      assert_golden("#{kind}-v2-migrated-v3.json", migrated, version: 3)
      assert_same migrated, Ibex::IR::Migration.to_v3(migrated)
    end
  end

  def test_schema_v1_to_v3_migration_preserves_all_unavailable_metadata
    grammar = Ibex::IR::Validator.validate(File.read(File.join(FIXTURE_ROOT, "grammar-v1.json")))
    migrated = Ibex::IR::Migration.to_version(grammar, to: 3)

    assert_equal 1, migrated.migration.fetch(:from_schema_version)
    assert_equal(
      Ibex::IR::Migration::UNAVAILABLE_V1_METADATA + Ibex::IR::Migration::UNAVAILABLE_V2_CONFIGURATION,
      migrated.migration.fetch(:unavailable)
    )
    migrated.parser_contract.to_h.each_value do |entry|
      assert_equal({ value: nil, explicit: false, loc: nil }, entry)
    end
  end

  def test_automaton_migration_upgrades_embedded_grammar_and_recalculates_digest
    source = File.read(File.join(FIXTURE_ROOT, "automaton-v1.json"))
    original = Ibex::IR::Validator.validate(source)
    migrated = Ibex::IR::Migration.to_v2(original)
    expected = "sha256:#{Digest::SHA256.hexdigest(Ibex::IR::Serialize.dump(migrated.grammar))}"

    assert_equal 2, migrated.schema_version
    assert_equal 2, migrated.grammar.schema_version
    refute_equal original.grammar_digest, migrated.grammar_digest
    assert_equal expected, migrated.grammar_digest
  end

  def test_automaton_constructor_rejects_mismatched_and_unknown_versions
    source = File.read(File.join(FIXTURE_ROOT, "automaton-v2.json"))
    automaton = Ibex::IR::Validator.validate(source)
    arguments = {
      grammar: automaton.grammar, states: automaton.states, conflict_summary: automaton.conflict_summary,
      algorithm: automaton.algorithm
    }

    mismatch = assert_raises(Ibex::Error) { Ibex::IR::Automaton.new(**arguments, schema_version: 1) }
    assert_includes mismatch.message, "requires Grammar IR v1, got v2"

    unknown = assert_raises(Ibex::Error) { Ibex::IR::Automaton.new(**arguments, schema_version: 99) }
    assert_includes unknown.message, "unsupported automaton schema_version 99"
  end

  private

  def build_pipeline
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "golden-v1.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    [grammar, Ibex::LALR::Builder.new(grammar).build]
  end

  def build_v3_pipeline
    grammar, = build_pipeline
    location = Ibex::Location.new(file: "golden-v3.y", line: 2, column: 1)
    contract = Ibex::IR::ParserContract.new(
      algorithm: Ibex::IR::ParserContract::Entry.new(
        :algorithm, value: :ielr, location: location, explicit: true
      ),
      entries: Ibex::IR::ParserContract::Entry.new(
        :entries, value: :shared, location: location, explicit: true
      ),
      cst_trivia: Ibex::IR::ParserContract::Entry.new(
        :cst_trivia, value: :balanced, location: location, explicit: true
      )
    )
    versioned = copy_grammar(grammar, contract)
    [versioned, Ibex::LALR::Builder.new(versioned, algorithm: :ielr).build]
  end

  # Constructor copying is deliberately local to this pre-syntax persistence
  # fixture. Source declarations will construct Grammar IR v3 directly.
  def copy_grammar(grammar, parser_contract)
    Ibex::IR::Grammar.new(
      class_name: grammar.class_name, superclass: grammar.superclass, start: grammar.start,
      mode: :extended, starts: grammar.starts,
      expect: grammar.expect, expect_rr: grammar.expect_rr,
      options: grammar.options.merge(cst: true), parser_parameters: grammar.parser_parameters,
      value_printers: grammar.value_printers, grammar_tests: grammar.grammar_tests,
      recovery: grammar.recovery, lexer: grammar.lexer, symbols: grammar.symbols,
      productions: grammar.productions, user_code: grammar.user_code,
      user_code_chunks: grammar.user_code_chunks, conversions: grammar.conversions,
      warnings: grammar.warnings, schema_version: 3, source_provenance: grammar.source_provenance,
      migration: nil, parser_contract: parser_contract
    )
  end

  def assert_golden(name, value, version:)
    path = File.join(FIXTURE_ROOT, name)
    actual = Ibex::IR::Serialize.dump(value)
    File.write(path, actual) if ENV[REFRESH_VARIABLE] == "1"
    assert File.file?(path), "missing #{name}; run #{REFRESH_VARIABLE}=1 ruby -Itest test/ir/golden_fixture_test.rb"
    expected = File.read(path)
    message = "#{name} changed; review schema-v#{version} compatibility, then refresh with #{REFRESH_VARIABLE}=1"
    assert_equal expected, actual, message

    loaded = Ibex::IR::Serialize.load(expected)
    assert_equal version, loaded.schema_version
    assert_equal expected, Ibex::IR::Serialize.dump(loaded), "#{name} must round-trip byte-for-byte"
  end
end
