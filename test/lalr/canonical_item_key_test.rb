# frozen_string_literal: true

require_relative "../test_helper"

class CanonicalItemKeyTest < Minitest::Test
  class TupleKeyBuilder < Ibex::LALR::Builder
    private

    def core_key(items)
      items.map { |production, dot, _lookahead| [production, dot] }.uniq.sort
    end

    def item_key(items)
      items.to_a.sort
    end
  end

  CANONICAL_CONFIGURATIONS = [
    { algorithm: :lr1 },
    { algorithm: :ielr },
    { algorithm: :lalr, lalr_strategy: :canonical_merge },
    { algorithm: :slr, lalr_strategy: :canonical_merge }
  ].freeze

  def test_numeric_keys_match_tuple_reference_for_canonical_consumers
    grammars = [
      normalize(nullable_recursive_grammar),
      normalize(multiple_entry_grammar, mode: :extended),
      high_id_grammar
    ]

    grammars.each do |grammar|
      CANONICAL_CONFIGURATIONS.each do |options|
        assert_reference_equivalence(grammar, **options)
      end
    end
  end

  def test_randomized_automata_and_generated_ruby_match_tuple_reference
    20.times do |seed|
      grammar = normalize(random_grammar(seed))
      CANONICAL_CONFIGURATIONS.each do |options|
        assert_reference_equivalence(grammar, **options)
      end
    end
  end

  def test_multiple_entries_with_entry_isolation_match_tuple_reference
    grammar = normalize(multiple_entry_grammar, mode: :extended)

    CANONICAL_CONFIGURATIONS.each do |options|
      assert_reference_equivalence(grammar, **options, entry_isolation: true)
    end
  end

  def test_packed_keys_are_collision_free_and_preserve_item_order
    grammar = high_id_grammar
    builder = Ibex::LALR::Builder.new(grammar, algorithm: :lr1)
    states, = builder.send(:canonical_collection)
    items = states.flat_map(&:to_a).uniq
    packed = packed_items(builder, items)

    assert_collision_free_order(items, packed)
    assert_boundary_items(grammar, items)
    states.each { |state| assert_state_keys(builder, state, packed) }
  end

  def test_packing_handles_large_integer_ids_without_machine_word_assumptions
    grammar = normalize(<<~GRAMMAR)
      class LargeIntegerKey
      token ITEM
      rule
      start: ITEM
      end
    GRAMMAR
    builder = Ibex::LALR::Builder.new(grammar, algorithm: :lr1)
    production_offset, dot_radix, lookahead_radix = builder.send(:canonical_key_radices)
    high_production = 2**130
    high_lookahead = grammar.terminals.map(&:id).max
    items = Set[
      [-1, 1, 0],
      [high_production, 0, high_lookahead],
      [high_production, 1, 0]
    ]
    expected = items.to_a.sort.map do |production, dot, lookahead|
      ((((production + production_offset) * dot_radix) + dot) * lookahead_radix) + lookahead
    end

    assert_equal expected, builder.send(:item_key, items)
    assert expected.all?(Integer)
    assert_operator expected.max, :>, 2**130
  end

  def test_direct_lalr_does_not_compute_canonical_key_radices
    grammar = normalize(<<~GRAMMAR)
      class DirectKey
      token ITEM
      rule
      start: list
      list: list ITEM | ITEM
      end
    GRAMMAR
    builder = Ibex::LALR::Builder.new(grammar)

    builder.build

    assert_nil builder.instance_variable_get(:@canonical_key_radices)
  end

  private

  def packed_items(builder, items)
    production_offset, dot_radix, lookahead_radix = builder.send(:canonical_key_radices)
    items.to_h do |production, dot, lookahead|
      core = ((production + production_offset) * dot_radix) + dot
      [[production, dot, lookahead], (core * lookahead_radix) + lookahead]
    end
  end

  def assert_collision_free_order(items, packed)
    sorted_by_packed = items.sort_by { |item| packed.fetch(item) }

    assert_equal items.length, packed.values.uniq.length
    assert_equal items.sort, sorted_by_packed
  end

  def assert_boundary_items(grammar, items)
    assert_includes items.map(&:first), -grammar.starts.length
    assert_includes items.map { |item| item.fetch(1) }, longest_rhs(grammar)
    assert_operator items.map(&:last).max, :>=, 127
  end

  def assert_state_keys(builder, state, packed)
    production_offset, dot_radix, = builder.send(:canonical_key_radices)
    expected = state.to_a.sort
    expected_cores = expected.map do |production, dot, _lookahead|
      ((production + production_offset) * dot_radix) + dot
    end.uniq

    assert_equal expected.map { |item| packed.fetch(item) }, builder.send(:item_key, state)
    assert_equal expected_cores, builder.send(:core_key, state)
  end

  def assert_reference_equivalence(grammar, **options)
    expected = TupleKeyBuilder.new(grammar, **options).build
    builder = Ibex::LALR::Builder.new(grammar, **options)
    actual = builder.build

    assert_equal expected.to_h, actual.to_h, options.inspect
    assert_equal Ibex::IR::Serialize.dump(expected), Ibex::IR::Serialize.dump(actual), options.inspect
    assert_equal generated_ruby(expected), generated_ruby(actual), options.inspect
    assert_equal actual.to_h, builder.build.to_h, "repeated #{options.inspect}"
  end

  def generated_ruby(automaton)
    Ibex::Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
  end

  def normalize(source, mode: :default)
    ast = Ibex::Frontend::Parser.new(source, file: "canonical-item-key.y", mode: mode).parse
    Ibex::Normalizer.new(ast, mode: mode).normalize
  end

  def nullable_recursive_grammar
    <<~GRAMMAR
      class NullableRecursiveKey
      token OPEN CLOSE ITEM COMMA
      rule
      start: OPEN values CLOSE
      values: values COMMA value | value |
      value: ITEM | OPEN values CLOSE
      end
    GRAMMAR
  end

  def multiple_entry_grammar
    <<~GRAMMAR
      class MultipleEntryKey
      pragma extended
      start program expression
      token A B C
      rule
      program: sequence B
      expression: sequence C
      sequence: sequence A |
      end
    GRAMMAR
  end

  def random_grammar(seed)
    random = Random.new(seed)
    tokens = Array.new(10) { |index| "TOKEN_#{index}" }
    selected = tokens.sample(7, random: random)
    <<~GRAMMAR
      class RandomKey#{seed}
      token #{tokens.join(' ')}
      rule
      start: sequence #{selected.fetch(0)} | nested #{selected.fetch(1)}
      sequence: sequence #{selected.fetch(2)} atom | atom |
      nested: #{selected.fetch(3)} sequence #{selected.fetch(4)} | sequence
      atom: #{selected.fetch(5)} | nested #{selected.fetch(6)}
      end
    GRAMMAR
  end

  def high_id_grammar
    terminal_names = Array.new(128) { |index| "TOKEN_#{index}" }
    symbols = [
      Ibex::IR::GrammarSymbol.new(id: 0, name: "$eof", kind: :terminal, reserved: true),
      Ibex::IR::GrammarSymbol.new(id: 1, name: "error", kind: :terminal, reserved: true)
    ]
    terminal_names.each_with_index do |name, index|
      symbols << Ibex::IR::GrammarSymbol.new(id: index + 2, name: name, kind: :terminal)
    end
    %w[program expression sequence].each do |name|
      symbols << Ibex::IR::GrammarSymbol.new(id: symbols.length, name: name, kind: :nonterminal)
    end
    program, expression, sequence = symbols.last(3).map(&:id)
    long_rhs = Array.new(40) { |index| index.even? ? 7 : 127 }
    productions = [
      production(0, program, [7, sequence, 127]),
      production(1, expression, [127, sequence, 7]),
      production(2, sequence, [sequence, 127]),
      production(3, sequence, []),
      production(4, sequence, long_rhs)
    ]
    Ibex::IR::Grammar.new(
      class_name: "HighIdKey", superclass: nil, start: "program", starts: %w[program expression sequence],
      mode: :extended, expect: 0, options: {}, symbols: symbols, productions: productions,
      user_code: {}, conversions: {}, warnings: []
    )
  end

  def production(id, lhs, rhs)
    Ibex::IR::Production.new(
      id: id, lhs: lhs, rhs: rhs, action: nil, precedence_override: nil, origin: { kind: :rule }
    )
  end

  def longest_rhs(grammar)
    grammar.productions.map { |production| production.rhs.length }.max
  end
end
