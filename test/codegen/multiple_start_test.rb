# frozen_string_literal: true

require_relative "../test_helper"

class MultipleStartCodegenTest < Minitest::Test
  SOURCE = <<~GRAMMAR
    class MultipleEntryParser
    pragma extended
    start program expression
    rule
    program: A B { result = :program }
    expression: A { result = :expression }
    end
    ---- inner
    attr_writer :tokens
    def next_token = @tokens.shift
  GRAMMAR

  COMPOSITE_CONFLICT_SOURCE = <<~GRAMMAR
    class CompositeEntries
    pragma extended
    start first second
    rule
    first: 'a' left 'd' | 'a' right 'e'
    second: 'a' left 'e' | 'a' right 'd'
    left: 'c'
    right: 'c'
    end
  GRAMMAR

  def test_shared_tables_generate_one_public_method_per_entry
    parser_class, automaton = generate

    assert_equal({ "program" => 0, "expression" => 1 }, automaton.entry_states)
    assert_equal({ program: 0, expression: 1 }, parser_class.const_get(:ENTRY_STATES))
    assert_equal :program, parse(parser_class, :parse_program, %i[A B])
    assert_equal :expression, parse(parser_class, :parse_expression, [:A])
    assert_equal :program, parse(parser_class, :do_parse, %i[A B])

    signature = Ibex::Codegen::RBS.new(automaton).generate
    assert_includes signature, "def parse_program: () -> untyped"
    assert_includes signature, "def parse_expression: () -> untyped"
  end

  def test_all_construction_algorithms_support_multiple_entries
    %i[slr lalr ielr lr1].each do |algorithm|
      parser_class, = generate(algorithm: algorithm)
      assert_equal :program, parse(parser_class, :parse_program, %i[A B])
      assert_equal :expression, parse(parser_class, :parse_expression, [:A])
    end
  end

  def test_plain_tables_support_entry_initial_states
    parser_class, = generate(table: :plain)

    assert_equal :expression, parse(parser_class, :parse_expression, [:A])
  end

  def test_entry_isolation_concatenates_independent_state_sets
    parser_class, automaton = generate(entry_isolation: true)

    assert_operator automaton.entry_states.fetch("expression"), :>, automaton.entry_states.fetch("program")
    assert_equal :program, parse(parser_class, :parse_program, %i[A B])
    assert_equal :expression, parse(parser_class, :parse_expression, [:A])
  end

  def test_shared_conflicts_are_attributed_and_composite_conflicts_disappear_when_isolated
    grammar = normalize(COMPOSITE_CONFLICT_SOURCE)
    shared = Ibex::LALR::Builder.new(grammar).build
    isolated = Ibex::LALR::Builder.new(grammar, entry_isolation: true).build
    conflicts = shared.states.flat_map(&:conflicts)

    assert_equal 2, shared.conflict_summary[:rr]
    assert_equal 0, isolated.conflict_summary[:rr]
    assert(conflicts.all? { |conflict| conflict[:entries] == %w[first second] })
    assert(conflicts.all? { |conflict| conflict[:composite] == true })
    report = Ibex::Codegen::Report.render(shared)
    assert_includes report, "resolution: {by: :definition_order, chose: 4}"
    assert_includes report, "composite: true"
    refute_includes report, ":composite=>true"
  end

  private

  def generate(algorithm: :lalr, table: :compact, entry_isolation: false)
    grammar = normalize(SOURCE)
    automaton = Ibex::LALR::Builder.new(
      grammar, algorithm: algorithm, entry_isolation: entry_isolation
    ).build
    namespace = Module.new
    namespace.module_eval(Ibex::Codegen::Ruby.new(automaton, table: table).generate, "multiple.rb")
    [namespace.const_get(:MultipleEntryParser), automaton]
  end

  def normalize(source)
    ast = Ibex::Frontend::Parser.new(source, file: "multiple.y", mode: :extended).parse
    Ibex::Normalizer.new(ast, mode: :extended).normalize
  end

  def parse(parser_class, method_name, tokens)
    parser = parser_class.new
    parser.tokens = tokens.map { |token| [token, nil] }
    parser.public_send(method_name)
  end
end
