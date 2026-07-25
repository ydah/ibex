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
