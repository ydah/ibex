# frozen_string_literal: true

require_relative "test_helper"

class TablesTest < Minitest::Test
  def test_plain_and_compact_tables_are_equivalent
    ast = Ibex::Frontend::Parser.new("class P\nrule\nstart: TOKEN\nend\n", file: "table.y").parse
    automaton = Ibex::LALR::Builder.new(Ibex::Normalizer.new(ast).normalize).build
    plain = Ibex::Tables.build(automaton, format: :plain)
    compact = Ibex::Tables.build(automaton, format: :compact)

    automaton.states.each do |state|
      automaton.grammar.symbols.each do |grammar_symbol|
        plain_action = plain.actions.fetch(state.id, {})[grammar_symbol.id]
        plain_goto = plain.gotos.fetch(state.id, {})[grammar_symbol.id]
        assert plain_action == compact.actions.lookup(state.id, grammar_symbol.id)
        assert plain_goto == compact.gotos.lookup(state.id, grammar_symbol.id)
      end
    end
  end

  def test_compact_rows_preserve_explicit_entries
    rows = [{ 1 => :a, 5 => :b }, {}, { 1 => :c, 3 => :d }]
    compact = Ibex::Tables::Compact.build(rows)
    actual_rows = rows.each_index.map { |index| compact.row(index) }
    assert_equal rows, actual_rows
    assert_nil compact.lookup(1, 1)
  end
end
