# frozen_string_literal: true

require_relative "test_helper"

class GrammarTestsRunnerTest < Minitest::Test
  GRAMMAR = <<~GRAMMAR
    class GrammarTestParser
    pragma extended
    %test accept "ab"
    %test reject "a"
    %test reject "!"
    rule
    start: 'a' 'b'
    end
    ---- inner
    def parse(source)
      raise ArgumentError, "lexical failure" if source == "!"

      @tokens = source.each_char.map { |character| [character, nil] }
      do_parse
    end
    def next_token = @tokens.shift || false
  GRAMMAR

  def test_runs_each_case_in_an_isolated_process_and_distinguishes_harness_errors
    results = Ibex::GrammarTests::Runner.new(automaton(GRAMMAR)).run

    assert_equal %i[accept reject error], results.map(&:actual)
    assert results.fetch(0).passed?
    assert results.fetch(1).passed?
    refute results.fetch(2).passed?
    assert_equal "ArgumentError", results.fetch(2).error_class
    assert_equal "lexical failure", results.fetch(2).error_message
    assert_equal [0], results.fetch(0).production_ids
    assert_empty results.fetch(2).production_ids

    coverage = Ibex::GrammarTests::Runner.new(automaton(GRAMMAR)).production_coverage(results)
    assert coverage.complete?
    assert coverage.meets?(100)
    assert_in_delta 100.0, coverage.percentage
  end

  def test_reports_missing_productions
    source = GRAMMAR.sub("start: 'a' 'b'", "start: 'a' 'b' | 'c'")
    runner = Ibex::GrammarTests::Runner.new(automaton(source))

    coverage = runner.production_coverage(runner.run)

    refute coverage.complete?
    refute coverage.meets?(100)
    assert_equal [1], coverage.missing_ids
    assert_in_delta 50.0, coverage.percentage
  end

  def test_rejects_empty_suites_and_required_constructor_parameters
    empty = GRAMMAR.lines.reject { |line| line.lstrip.start_with?("%test") }.join
    error = assert_raises(Ibex::Error) { Ibex::GrammarTests::Runner.new(automaton(empty)).run }
    assert_includes error.message, "grammar declares no %test cases"

    parameterized = GRAMMAR.sub("pragma extended\n", "pragma extended\n%param context\n")
    error = assert_raises(Ibex::Error) { Ibex::GrammarTests::Runner.new(automaton(parameterized)).run }
    assert_includes error.message, "required %param declarations"
  end

  private

  def automaton(source)
    ast = Ibex::Frontend::Parser.new(source, file: "grammar-tests.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    Ibex::LALR::Builder.new(grammar).build
  end
end
