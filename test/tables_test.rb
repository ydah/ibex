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

  def test_compact_layout_remains_deterministic_when_rows_share_anchor_columns
    rows = [
      { 1 => :a, 5 => :b },
      { 1 => :c, 3 => :d },
      { 1 => :e, 5 => :f },
      { 2 => :g },
      {},
      { 1 => :h, 2 => :i, 5 => :j }
    ]

    compact = Ibex::Tables::Compact.build(rows)

    assert_equal [2, 3, 7, 7, 0, 0], compact.offsets
    assert_equal [nil, :h, :i, :a, :c, :j, :d, :b, :e, :g, nil, nil, :f], compact.values
    assert_equal [nil, 5, 5, 0, 1, 5, 1, 0, 2, 3, nil, nil, 2], compact.checks
    actual_rows = rows.each_index.map { |row| compact.row(row) }
    assert_equal rows, actual_rows
  end

  def test_optimized_offset_search_matches_naive_layout
    random = Random.new(12_345)
    rows = Array.new(80) do |row|
      columns = (0..24).to_a.sample(random.rand(0..6), random: random)
      columns.to_h { |column| [column, [row, column]] }
    end
    expected_offsets, expected_values, expected_checks = naive_layout(rows)

    compact = Ibex::Tables::Compact.build(rows)

    assert_equal expected_offsets, compact.offsets
    assert_equal expected_values, compact.values
    assert_equal expected_checks, compact.checks
  end

  private

  def naive_layout(rows)
    offsets = Array.new(rows.length, 0)
    values = []
    checks = []
    rows.each_index.sort_by { |row| [-rows[row].length, row] }.each do |row|
      offset = 0
      offset += 1 while rows[row].keys.any? { |column| checks[offset + column] }
      offsets[row] = offset
      rows[row].each do |column, value|
        values[offset + column] = value
        checks[offset + column] = row
      end
    end
    [offsets, values, checks]
  end

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
