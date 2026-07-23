# frozen_string_literal: true

require_relative "../test_helper"

class DiagnosticsTest < Minitest::Test
  def test_warns_about_unused_precedence_and_declared_but_unreachable_terminals
    grammar = normalize(<<~GRAMMAR)
      class P
      token LIVE DEAD
      preclow
      left UNUSED_PRECEDENCE
      right USED_PRECEDENCE
      prechigh
      rule
      start: LIVE = USED_PRECEDENCE
      dead: DEAD
      end
    GRAMMAR

    unused_precedence = grammar.warnings.find { |warning| warning[:type] == :unused_precedence }
    assert_equal "UNUSED_PRECEDENCE", unused_precedence[:symbol]
    assert_equal 4, unused_precedence.dig(:loc, :line)

    unreachable_terminal = grammar.warnings.find { |warning| warning[:type] == :unreachable_terminal }
    assert_equal "DEAD", unreachable_terminal[:symbol]
    assert_equal 2, unreachable_terminal.dig(:loc, :line)
    refute(grammar.warnings.any? do |warning|
      warning[:type] == :unused_terminal && warning[:symbol] == "DEAD"
    end)
    refute(grammar.warnings.any? do |warning|
      warning[:type] == :unused_precedence && warning[:symbol] == "USED_PRECEDENCE"
    end)

    dumped = Ibex::IR::Serialize.dump(grammar)
    assert_equal dumped, Ibex::IR::Serialize.dump(Ibex::IR::Serialize.load(dumped))
  end

  def test_precedence_symbol_used_in_a_rhs_is_not_reported_as_unused
    grammar = normalize(<<~GRAMMAR)
      class P
      preclow
      left '+'
      prechigh
      rule
      expression: expression '+' expression | NUMBER
      end
    GRAMMAR

    refute(grammar.warnings.any? { |warning| warning[:type] == :unused_precedence })
  end

  private

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "diagnostics.y").parse
    Ibex::Normalizer.new(ast).normalize
  end
end
