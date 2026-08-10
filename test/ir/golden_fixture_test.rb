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

  def test_current_grammar_ir_golden_fixture
    grammar, = build_pipeline
    assert_golden("grammar.json", grammar)
  end

  def test_current_automaton_ir_golden_fixture
    _, automaton = build_pipeline
    assert_golden("automaton.json", automaton)
  end

  def test_current_ir_rejects_explicitly_old_versions
    [2, 3, 99].each do |version|
      error = assert_raises(Ibex::Error) do
        Ibex::IR::Validator.validate(JSON.generate(ibex_ir: "grammar", schema_version: version))
      end
      assert_includes error.message, "unsupported schema_version #{version.inspect}"
    end
  end

  private

  def build_pipeline
    ast = Ibex::Frontend::Parser.new(SOURCE, file: "golden.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    location = Ibex::Location.new(file: "golden.y", line: 2, column: 1)
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
    grammar = Ibex::IR::Grammar.new(
      class_name: grammar.class_name, superclass: grammar.superclass, start: grammar.start,
      expect: grammar.expect, options: grammar.options.merge(cst: true), symbols: grammar.symbols,
      productions: grammar.productions, user_code: grammar.user_code, conversions: grammar.conversions,
      warnings: grammar.warnings, user_code_chunks: grammar.user_code_chunks,
      source_provenance: { file: "golden.y", root: nil, byte_span: nil }, expect_rr: grammar.expect_rr,
      parser_parameters: grammar.parser_parameters, value_printers: grammar.value_printers,
      grammar_tests: grammar.grammar_tests, recovery: grammar.recovery, lexer: grammar.lexer,
      mode: :extended, starts: grammar.starts, parser_contract: contract
    )
    [grammar, Ibex::LALR::Builder.new(grammar, algorithm: :ielr).build]
  end

  def assert_golden(name, value)
    path = File.join(FIXTURE_ROOT, name)
    actual = Ibex::IR::Serialize.dump(value)
    File.write(path, actual) if ENV[REFRESH_VARIABLE] == "1"
    assert File.file?(path), "missing #{name}; run #{REFRESH_VARIABLE}=1 ruby -Itest test/ir/golden_fixture_test.rb"
    expected = File.read(path)
    assert_equal expected, actual, "#{name} changed; review the current IR contract before refreshing"

    loaded = Ibex::IR::Validator.validate(expected)
    assert_equal Ibex::IR::SCHEMA_VERSION, loaded.schema_version
    assert_equal expected, Ibex::IR::Serialize.dump(loaded), "#{name} must round-trip byte-for-byte"
  end
end
