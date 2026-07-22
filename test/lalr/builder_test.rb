# frozen_string_literal: true

require_relative "../test_helper"

class LALRBuilderTest < Minitest::Test
  def build(source)
    ast = Ibex::Frontend::Parser.new(source, file: "builder.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    Ibex::LALR::Builder.new(grammar).build
  end

  def test_builds_textbook_lalr_collection_deterministically
    source = <<~GRAMMAR
      class P
      rule
      start: pair pair
      pair: 'c' pair | 'd'
      end
    GRAMMAR
    first = build(source)
    second = build(source)
    assert_equal 7, first.states.length
    assert_equal Ibex::IR::Serialize.dump(first), Ibex::IR::Serialize.dump(second)
    assert_equal 0, first.conflict_summary[:sr]
    assert(first.states.any? { |state| state.actions.values.any? { |action| action[:type] == :accept } })
  end

  def test_dangling_else_records_default_shift_and_expectation
    automaton = build(<<~GRAMMAR)
      class P
      token IF THEN ELSE ID
      expect 1
      rule
      stmt: IF expr THEN stmt
          | IF expr THEN stmt ELSE stmt
          | ID
      expr: ID
      end
    GRAMMAR
    assert_equal({ sr: 1, rr: 0, expected_sr: 1, expectation_met: true }, automaton.conflict_summary)
    conflict = automaton.states.flat_map(&:conflicts).find { |item| item[:type] == :shift_reduce }
    assert_equal "ELSE", conflict[:symbol]
    assert_equal({ by: :default_shift, chose: :shift }, conflict[:resolution])
  end

  def test_precedence_associativity_and_nonassoc_resolve_conflicts
    automaton = build(<<~GRAMMAR)
      class P
      token NUM
      preclow
      nonassoc '<'
      left '+'
      left '*'
      right '^'
      right UMINUS
      prechigh
      rule
      expr: expr '+' expr
          | expr '*' expr
          | expr '^' expr
          | expr '<' expr
          | '-' expr = UMINUS
          | NUM
      end
    GRAMMAR
    conflicts = automaton.states.flat_map(&:conflicts).select { |item| item[:type] == :shift_reduce }
    assert(conflicts.any? { |item| item[:resolution][:chose] == :reduce })
    assert(conflicts.any? { |item| item[:resolution][:chose] == :shift })
    assert(conflicts.any? { |item| item[:resolution][:chose] == :error })
    assert(automaton.states.any? { |state| state.actions.values.any? { |action| action[:type] == :error } })
  end

  def test_reduce_reduce_uses_definition_order
    automaton = build(<<~GRAMMAR)
      class P
      rule
      start: first | second
      first: TOKEN
      second: TOKEN
      end
    GRAMMAR
    conflict = automaton.states.flat_map(&:conflicts).find { |item| item[:type] == :reduce_reduce }
    assert_equal [2, 3], conflict[:reductions]
    assert_equal 2, conflict[:resolution][:chose]
    assert_equal 1, automaton.conflict_summary[:rr]
  end

  def test_automaton_round_trip_and_report
    automaton = build("class P\nrule\nstart: TOKEN\nend\n")
    dumped = Ibex::IR::Serialize.dump(automaton)
    assert_equal dumped, Ibex::IR::Serialize.dump(Ibex::IR::Serialize.load(dumped))
    report = Ibex::Codegen::Report.render(automaton)
    assert_includes report, "State 0"
    assert_includes report, "$accept ->"
    assert_includes report, "Conflicts: 0 shift/reduce"
  end
end
