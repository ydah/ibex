# frozen_string_literal: true

require_relative "test_helper"

class TablesTest < Minitest::Test
  cover "Ibex::Tables::Compact#initialize" if ENV["IBEX_MUTATION"] == "1"

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
    assert_equal :d, compact.dense_values.fetch((2 * compact.dense_width) + 3)
  end

  def test_compact_table_owns_an_immutable_layout
    offsets = [0]
    values = [:value]
    checks = [0]
    compact = Ibex::Tables::Compact.new(offsets: offsets, values: values, checks: checks, row_count: 1)

    assert_predicate compact, :frozen?
    assert_same offsets, compact.offsets
    assert_same values, compact.values
    assert_same checks, compact.checks
    assert_predicate compact.offsets, :frozen?
    assert_predicate compact.values, :frozen?
    assert_predicate compact.checks, :frozen?
    assert_equal 1, compact.row_count
  end

  def test_compact_actions_round_trip_integer_codes_through_compatible_lookup
    rows = [
      { 0 => [:accept], 2 => [:shift, 3] },
      { 0 => [:reduce, 4], 1 => [:error] }
    ]

    compact = Ibex::Tables::CompactActions.build(rows)

    assert_instance_of Ibex::Tables::CompactActions, compact
    assert compact.codes.compact.all?(Integer)
    assert_equal Ibex::Tables::CompactActions.pack(compact.lookup(0, 2)),
                 compact.dense_codes.fetch((0 * compact.column_count) + 2)
    assert_equal rows[0], compact.row(0)
    assert_equal rows[1], compact.row(1)
    rows.each_with_index do |row, state|
      row.each { |token, action| assert_equal action, compact.lookup(state, token) }
    end
    rows.flat_map(&:values).each do |action|
      assert_equal action, Ibex::Tables::CompactActions.unpack(Ibex::Tables::CompactActions.pack(action))
    end
  end

  def test_legacy_compact_action_codes_are_normalized
    packed = Ibex::Tables::PackedIntegers
    compact = Ibex::Tables::CompactActions.packed(
      packed.encode([0]), packed.encode([0, 1, 4, 7]), packed.encode([0, 0, 0, 0]), row_count: 1
    )

    assert_equal [:accept], compact.lookup(0, 0)
    assert_equal [:error], compact.lookup(0, 1)
    assert_equal [:shift, 1], compact.lookup(0, 2)
    assert_equal [:reduce, 2], compact.lookup(0, 3)
  end

  def test_packed_integer_literals_round_trip_nil_and_multibyte_values
    values = [nil, 0, 1, 127, 128, 16_384]
    encoded = Ibex::Tables::PackedIntegers.encode(values)

    assert_equal values, Ibex::Tables::PackedIntegers.decode(encoded)
    assert_equal values.drop(1), Ibex::Tables::PackedIntegers.decode_required(
      Ibex::Tables::PackedIntegers.encode(values.drop(1))
    )
    assert_raises(ArgumentError) { Ibex::Tables::PackedIntegers.decode_required(encoded) }
    assert_raises(ArgumentError) { Ibex::Tables::PackedIntegers.encode([-1]) }
  end

  def test_packed_signed_integer_literals_round_trip
    values = [nil, 0, -1, 1, -127, 128, -16_384, 16_384]

    assert_equal values, Ibex::Tables::PackedIntegers.decode_signed(
      Ibex::Tables::PackedIntegers.encode_signed(values)
    )
  end

  def test_compact_tables_load_packed_integer_layouts
    rows = [{ 0 => [:accept], 2 => [:shift, 3] }, { 0 => [:reduce, 4] }]
    actions = Ibex::Tables::CompactActions.build(rows)
    packed_actions = Ibex::Tables::CompactActions.packed(
      Ibex::Tables::PackedIntegers.encode(actions.offsets),
      Ibex::Tables::PackedIntegers.encode_signed(actions.codes),
      Ibex::Tables::PackedIntegers.encode(actions.checks),
      row_count: actions.row_count,
      encoding: :signed
    )

    assert_equal(rows.map.with_index { |_, index| actions.row(index) },
                 rows.map.with_index { |_, index| packed_actions.row(index) })
  end

  def test_compact_productions_keep_parallel_hot_fields_and_compatible_entries
    productions = [
      {
        lhs: 3, length: 1, action: :_ibex_action_0, values_action: true, # rubocop:disable Naming/VariableNumber
        borrowed_values_action: true, location_names: { item: 0 }.freeze
      },
      { lhs: 4, length: 0, action: nil }
    ]

    compact = Ibex::Tables::CompactProductions.build(productions)

    assert_instance_of Ibex::Tables::CompactProductions, compact
    assert_equal [3, 4], compact.lhs_ids
    assert_equal [1, 0], compact.lengths
    assert_equal [:_ibex_action_0, nil], compact.actions # rubocop:disable Naming/VariableNumber
    assert_equal productions, compact
    assert compact.direct_values?
    assert compact.all?(&:frozen?)
  end

  def test_compact_productions_derive_generated_action_symbols_from_packed_flags
    source = Ibex::Tables::PackedIntegers
    compact = Ibex::Tables::CompactProductions.packed(
      source.encode([3, 4]), source.encode([1, 0]), source.encode([3, 0])
    )

    assert_equal [:_ibex_action_0, nil], compact.actions # rubocop:disable Naming/VariableNumber
    assert_equal true, compact.fetch(0)[:borrowed_values_action]
    assert_nil compact.fetch(1)[:action]
  end

  def test_compact_productions_reject_inconsistent_parallel_data
    assert_raises(ArgumentError) do
      Ibex::Tables::CompactProductions.new(lhs_ids: [1], lengths: [], actions: [], flags: [])
    end
    assert_raises(ArgumentError) do
      # rubocop:disable Naming/VariableNumber
      Ibex::Tables::CompactProductions.new(lhs_ids: [1], lengths: [0], actions: [:_ibex_action_0], flags: [2])
      # rubocop:enable Naming/VariableNumber
    end
    assert_raises(ArgumentError) do
      positional_and_values = Ibex::Tables::CompactProductions::POSITIONAL_ACTION |
                              Ibex::Tables::CompactProductions::VALUES_ACTION
      Ibex::Tables::CompactProductions.new(
        lhs_ids: [1], lengths: [1], actions: [:_ibex_action_0], flags: [positional_and_values] # rubocop:disable Naming/VariableNumber
      )
    end
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
