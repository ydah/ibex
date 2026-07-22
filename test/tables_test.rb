# frozen_string_literal: true

require_relative "test_helper"

class TablesTest < Minitest::Test
  def test_plain_and_compact_tables_are_equivalent
    source = <<~GRAMMAR
      class P
      token A B C BAD
      rule
      start: list
      list: list item | item
      item: A | B | C
      end
    GRAMMAR
    ast = Ibex::Frontend::Parser.new(source, file: "table.y").parse
    automaton = Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
    plain = Ibex::Tables.build(automaton, format: :plain)
    compact = Ibex::Tables.build(automaton, format: :compact)

    automaton.states.each { |state| assert_state_tables(automaton, plain, compact, state) }
  end

  def test_compact_rows_preserve_explicit_entries
    rows = [{ 1 => :a, 5 => :b }, {}, { 1 => :c, 3 => :d }]
    compact = Ibex::Tables::Compact.build(rows)
    actual_rows = rows.each_index.map { |index| compact.row(index) }
    assert_equal rows, actual_rows
    assert_nil compact.lookup(1, 1)
    assert_nil compact.lookup(0, -1)
    assert_nil compact.lookup(0, 100)
    assert_empty compact.row(-1)
  end

  private

  def assert_state_tables(automaton, plain, compact, state)
    expected_default = plain.default_actions[state.id]
    actual_default = compact.default_actions[state.id]
    expected_default ? assert_equal(expected_default, actual_default) : assert_nil(actual_default)
    automaton.grammar.symbols.each { |grammar_symbol| assert_table_cells(plain, compact, state, grammar_symbol) }
  end

  def assert_table_cells(plain, compact, state, grammar_symbol)
    row = state.id
    column = grammar_symbol.id
    assert_optional_equal(plain.actions.fetch(row, {})[column], compact.actions.lookup(row, column))
    assert_optional_equal(plain.gotos.fetch(row, {})[column], compact.gotos.lookup(row, column))
  end

  def assert_optional_equal(expected, actual)
    expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
  end
end
