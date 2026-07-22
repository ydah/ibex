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

  def test_grammar_ir_schema_v1_golden_fixture
    grammar, = build_pipeline
    assert_golden("grammar-v1.json", grammar)
  end

  def test_automaton_ir_schema_v1_golden_fixture
    _, automaton = build_pipeline
    assert_golden("automaton-v1.json", automaton)
  end

  private

  def build_pipeline
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "golden-v1.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    [grammar, Ibex::LALR::Builder.new(grammar).build]
  end

  def assert_golden(name, value)
    path = File.join(FIXTURE_ROOT, name)
    actual = Ibex::IR::Serialize.dump(value)
    File.write(path, actual) if ENV[REFRESH_VARIABLE] == "1"
    assert File.file?(path), "missing #{name}; run #{REFRESH_VARIABLE}=1 ruby -Itest test/ir/golden_fixture_test.rb"
    expected = File.read(path)
    message = "#{name} changed; review schema-v1 compatibility, then refresh with #{REFRESH_VARIABLE}=1"
    assert_equal expected, actual, message

    loaded = Ibex::IR::Serialize.load(expected)
    assert_equal 1, loaded.schema_version
    assert_equal expected, Ibex::IR::Serialize.dump(loaded), "#{name} must round-trip byte-for-byte"
  end
end
