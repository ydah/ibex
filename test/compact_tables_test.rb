# frozen_string_literal: true

require_relative "test_helper"

class CompactTablesTest < Minitest::Test
  def test_compact_table_can_skip_the_dense_layout
    compact = Ibex::Tables::Compact.build([{ 1 => :value }], dense: false)

    assert_nil compact.dense_values
    assert_nil compact.dense_width
    assert_equal :value, compact.lookup(0, 1)
  end

  def test_compact_tables_bound_optional_dense_layouts
    column = Ibex::Tables::Compact::DENSE_CELL_LIMIT
    compact = Ibex::Tables::Compact.build([{ column => :value }])
    actions = Ibex::Tables::CompactActions.build([{ column => [:accept] }])

    assert_nil compact.dense_values
    assert_nil compact.dense_width
    assert_nil actions.dense_codes
    assert_nil actions.column_count
    assert_equal :value, compact.lookup(0, column)
    assert_equal [:accept], actions.lookup(0, column)
  end
end
