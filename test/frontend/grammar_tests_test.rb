# frozen_string_literal: true

require_relative "../test_helper"

class FrontendGrammarTestsTest < Minitest::Test
  def test_parses_formats_and_normalizes_grammar_tests
    source = <<~'GRAMMAR'
      class P
      pragma extended
      %test accept "1+2"
      %test reject "1+\n"
      rule
      start: TOKEN
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "grammar.y").parse
    tests = ast.declarations.grep(Ibex::Frontend::AST::GrammarTest)

    assert_equal %i[accept reject], tests.map(&:expectation)
    assert_equal ["1+2", "1+\n"], tests.map(&:source)
    assert_equal(
      [
        { expectation: :accept, source: "1+2", loc: { file: "grammar.y", line: 3, column: 1 } },
        { expectation: :reject, source: "1+\n", loc: { file: "grammar.y", line: 4, column: 1 } }
      ],
      Ibex::Normalizer.new(ast).normalize.grammar_tests
    )

    formatted = Ibex::Frontend::Formatter.format(source, file: "grammar.y")
    assert_equal formatted, Ibex::Frontend::Formatter.format(formatted, file: "grammar.y")
  end

  def test_requires_extended_mode_known_expectation_and_double_quotes
    cases = {
      "%test accept \"ok\"" => "%test require extended mode",
      "pragma extended\n%test maybe \"ok\"" => "expected accept or reject, got maybe",
      "pragma extended\n%test accept 'ok'" => "%test source must use a double-quoted string"
    }

    cases.each do |declaration, message|
      error = assert_raises(Ibex::Error) do
        parse("class P\n#{declaration}\nrule\nstart: TOKEN\nend\n")
      end
      assert_includes error.message, message
    end
  end

  def test_dsl_preserves_accept_and_reject_tests
    ast = Ibex::Frontend::DSL.grammar(class_name: "P") do |grammar|
      grammar.test_accept("ok")
      grammar.test_reject("bad")
      grammar.rule(:start) { |rule| rule.alt(:TOKEN) }
    end

    tests = Ibex::Normalizer.new(ast, mode: :extended).normalize.grammar_tests
    assert_equal(
      [[:accept, "ok"], [:reject, "bad"]],
      tests.map { |test| [test[:expectation], test[:source]] }
    )
  end

  private

  def parse(source)
    Ibex::Frontend::Parser.new(source, file: "grammar.y").parse
  end
end
