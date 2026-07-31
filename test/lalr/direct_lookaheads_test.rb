# frozen_string_literal: true

require_relative "../test_helper"

# rubocop:disable Metrics/ClassLength -- direct-construction invariants share private grammar/reference helpers.
class DirectLookaheadsTest < Minitest::Test
  Terminal = Struct.new(:id, keyword_init: true)
  StartSymbol = Struct.new(:id, keyword_init: true)
  Grammar = Struct.new(:terminals, :productions, :start, :start_symbol, keyword_init: true) do
    def symbol(name)
      start_symbol if name == start
    end
  end

  def test_terminal_id_lookup_reuses_large_bit_masks
    skip "runtime allocation counter unavailable" unless TestRuntimeCapabilities.allocation_counter?

    iterations = 500
    ids = [100, 101, 102]
    lookaheads = direct_lookaheads(ids)
    bits = ids.sum { |id| 1 << id }

    selected = lookaheads.send(:terminal_ids, bits)

    assert_equal ids, selected
    assert_same selected, lookaheads.send(:terminal_ids, bits)
    assert_predicate selected, :frozen?
    assert_equal [100, 102], lookaheads.send(:terminal_ids, (1 << 102) | (1 << 100))
    cached_allocations = measure_allocations(iterations) { lookaheads.send(:terminal_ids, bits) }
    shifted_allocations = measure_allocations(iterations) do
      ids.select { |id| bits.anybits?(1 << id) }
    end

    assert_operator cached_allocations, :<, shifted_allocations * 0.8
  end

  def test_rhs_arrays_are_reused
    grammar, lookaheads = recursive_list_lookaheads
    assert_same lookaheads.send(:rhs_for, -1), lookaheads.send(:rhs_for, -1)
    grammar.productions.each do |production|
      assert_same production.rhs, lookaheads.send(:rhs_for, production.id)
    end
  end

  def test_all_valid_item_cores_are_canonical_and_frozen
    grammar, lookaheads = recursive_list_lookaheads
    (0..lookaheads.send(:rhs_for, -1).length).each do |dot|
      augmented = lookaheads.send(:item_core, -1, dot)

      assert_same augmented, lookaheads.send(:item_core, -1, dot)
      assert_equal [-1, dot], augmented
      assert_predicate augmented, :frozen?
    end
    grammar.productions.each do |production|
      (0..production.rhs.length).each do |dot|
        item = lookaheads.send(:item_core, production.id, dot)

        assert_same item, lookaheads.send(:item_core, production.id, dot)
        assert_equal [production.id, dot], item
        assert_predicate item, :frozen?
      end
    end
  end

  def test_repeated_lr0_collections_reuse_canonical_item_cores
    _grammar, lookaheads = recursive_list_lookaheads
    first, = lookaheads.send(:lr0_collection)
    second, = lookaheads.send(:lr0_collection)
    first.flat_map(&:to_a).zip(second.flat_map(&:to_a)).each do |first_core, second_core|
      assert_same lookaheads.send(:item_core, *first_core), first_core
      assert_same first_core, second_core
      assert_predicate first_core, :frozen?
    end
  end

  def test_encoded_item_keys_are_collision_free_for_every_valid_core
    grammar, lookaheads = recursive_list_lookaheads
    cores = (0..lookaheads.send(:rhs_for, -1).length).map do |dot|
      lookaheads.send(:item_core, -1, dot)
    end
    grammar.productions.each do |production|
      (0..production.rhs.length).each do |dot|
        cores << lookaheads.send(:item_core, production.id, dot)
      end
    end

    keys = cores.map { |core| lookaheads.send(:item_key, Set[core]).fetch(0) }

    assert_equal cores.length, keys.uniq.length
    assert(keys.all? { |key| key.is_a?(Integer) && key >= 0 })
  end

  def test_encoded_propagation_nodes_are_collision_free_for_every_item_occurrence
    _grammar, lookaheads = recursive_list_lookaheads
    states, = lookaheads.send(:lr0_collection)
    nodes = states.each_with_index.flat_map do |items, state_id|
      items.map do |production_id, dot|
        lookaheads.send(:node_id, state_id, production_id, dot)
      end
    end

    assert_equal states.sum(&:length), nodes.uniq.length
    assert(nodes.all? { |node| node.is_a?(Integer) && node >= 0 })
  end

  def test_grouped_shifted_kernels_match_the_previous_lr0_collection
    _grammar, lookaheads = expression_lookaheads

    expected_states, expected_transitions = legacy_lr0_collection(lookaheads)
    states, transitions = lookaheads.send(:lr0_collection)
    expected_items = expected_states.map { |state| state.to_a.sort }
    actual_items = states.map { |state| state.to_a.sort }

    assert_equal expected_items, actual_items
    assert_equal expected_transitions, transitions
  end

  def test_lr0_transitions_keep_symbol_ids_in_sorted_insertion_order
    _grammar, lookaheads = expression_lookaheads
    _states, transitions = lookaheads.send(:lr0_collection)

    transitions.each do |edges|
      assert_equal edges.keys.sort, edges.keys
    end
  end

  def test_shifted_kernels_support_sparse_symbol_ids_and_multiple_items_per_symbol
    grammar = sparse_symbol_grammar
    lookaheads = Ibex::LALR::DirectLookaheads.new(grammar, Object.new)
    items = Set[
      lookaheads.send(:item_core, -1, 0),
      lookaheads.send(:item_core, 0, 0),
      lookaheads.send(:item_core, 1, 0),
      lookaheads.send(:item_core, 2, 0)
    ]

    kernels = lookaheads.send(:shifted_kernels, items)

    assert_equal [7, 101, 103], kernels.keys.sort
    assert_equal Set[
      lookaheads.send(:item_core, 0, 1),
      lookaheads.send(:item_core, 1, 1)
    ], kernels.fetch(101)
    assert_equal Set[lookaheads.send(:item_core, 2, 1)], kernels.fetch(7)
    assert_equal Set[lookaheads.send(:item_core, -1, 1)], kernels.fetch(103)
  end

  def test_multi_entry_grammar_keeps_the_canonical_merge_collection
    grammar = normalize(<<~GRAMMAR, mode: :extended)
      class P
      pragma extended
      start first second
      token A B
      rule
      first: A
      second: B
      end
    GRAMMAR

    direct_default = Ibex::LALR::Builder.new(grammar).build
    explicit_reference = Ibex::LALR::Builder.new(grammar, lalr_strategy: :canonical_merge).build

    assert_equal Ibex::IR::Serialize.dump(explicit_reference), Ibex::IR::Serialize.dump(direct_default)
    assert_equal :canonical_merge_multi_entry, Ibex::LALR::Builder.new(grammar).tap(&:build).metrics.strategy
  end

  def test_grouped_shifted_kernels_reduce_lr0_collection_allocations
    skip "runtime allocation counter unavailable" unless TestRuntimeCapabilities.allocation_counter?

    _grammar, lookaheads = expression_lookaheads
    iterations = 30

    grouped_allocations = measure_allocations(iterations) { lookaheads.send(:lr0_collection) }
    legacy_allocations = measure_allocations(iterations) { legacy_lr0_collection(lookaheads) }

    assert_operator grouped_allocations, :<, legacy_allocations * 0.9
  end

  def test_canonical_item_core_lookup_avoids_per_lookup_allocation
    skip "runtime allocation counter unavailable" unless TestRuntimeCapabilities.allocation_counter?

    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM
      rule
      start: ITEM
      end
    GRAMMAR
    lookaheads = Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))
    production = grammar.productions.fetch(0)
    iterations = 500

    cached_allocations = measure_allocations(iterations) do
      lookaheads.send(:item_core, production.id, production.rhs.length)
    end
    constructed_allocations = measure_allocations(iterations) do
      [production.id, production.rhs.length]
    end

    assert_operator cached_allocations, :<, constructed_allocations * 0.1
  end

  def test_canonical_item_core_lookup_rejects_invalid_positions
    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM
      rule
      start: ITEM
      end
    GRAMMAR
    lookaheads = Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))

    assert_raises(IndexError) { lookaheads.send(:item_core, -2, 0) }
    assert_raises(IndexError) { lookaheads.send(:item_core, -1, -1) }
    assert_raises(IndexError) { lookaheads.send(:item_core, -1, 2) }
    assert_raises(IndexError) { lookaheads.send(:item_core, 0, -1) }
    assert_raises(IndexError) { lookaheads.send(:item_core, 0, 2) }
    assert_raises(IndexError) { lookaheads.send(:item_core, 1, 0) }
  end

  def test_lr0_and_lookahead_maps_share_canonical_item_core_keys
    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM COMMA
      rule
      start: list
      list: list COMMA ITEM | ITEM
      end
    GRAMMAR
    lookaheads = Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))
    states, = lookaheads.send(:lr0_collection)
    maps = lookaheads.send(:empty_lookaheads, states)

    states.zip(maps).each do |state, items|
      state.each do |item|
        canonical = lookaheads.send(:item_core, *item)
        mapped_item = items.keys.find { |key| key.equal?(item) }

        assert_same canonical, item
        assert_same item, mapped_item
      end
    end
  end

  def test_closure_reuses_canonical_initial_item_cores
    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM
      rule
      start: list
      list: list ITEM |
      end
    GRAMMAR
    lookaheads = Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))
    first = lookaheads.send(:closure, Set[lookaheads.send(:item_core, -1, 0)])
    second = lookaheads.send(:closure, Set[lookaheads.send(:item_core, -1, 0)])
    grammar.productions.each do |production|
      first_core = first.find { |production_id, dot| production_id == production.id && dot.zero? }
      second_core = second.find { |production_id, dot| production_id == production.id && dot.zero? }
      next unless first_core

      assert_same lookaheads.send(:item_core, production.id, 0), first_core
      assert_same first_core, second_core
      assert_predicate first_core, :frozen?
    end
  end

  def test_nullable_recursive_propagation_matches_canonical_reference
    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM COMMA END
      rule
      start: sequence END
      sequence: sequence separator ITEM | optional
      optional: ITEM optional |
      separator: COMMA |
      end
    GRAMMAR

    direct = Ibex::LALR::Builder.new(grammar).build
    reference = Ibex::LALR::Builder.new(grammar, lalr_strategy: :canonical_merge).build

    assert_equal Ibex::IR::Serialize.dump(reference), Ibex::IR::Serialize.dump(direct)
  end

  def test_cached_augmented_rhs_avoids_per_lookup_allocation
    skip "runtime allocation counter unavailable" unless TestRuntimeCapabilities.allocation_counter?

    grammar = normalize(<<~GRAMMAR)
      class P
      rule
      start:
      end
    GRAMMAR
    lookaheads = Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))
    iterations = 500
    start = grammar.symbol(grammar.start)

    cached_allocations = measure_allocations(iterations) { lookaheads.send(:rhs_for, -1) }
    uncached_allocations = measure_allocations(iterations) { [start.id] }

    assert_operator cached_allocations, :<, uncached_allocations * 0.1
  end

  private

  def direct_lookaheads(ids)
    grammar = Grammar.new(
      terminals: ids.map { |id| Terminal.new(id: id) },
      productions: [],
      start: "start",
      start_symbol: StartSymbol.new(id: 0)
    )
    Ibex::LALR::DirectLookaheads.new(grammar, Object.new)
  end

  def recursive_list_lookaheads
    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM
      rule
      start: list
      list: list ITEM |
      end
    GRAMMAR
    [grammar, Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))]
  end

  def expression_lookaheads
    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM PLUS STAR LPAREN RPAREN
      rule
      start: expression
      expression: expression PLUS term | term
      term: term STAR atom | atom
      atom: LPAREN expression RPAREN | ITEM
      end
    GRAMMAR
    [grammar, Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))]
  end

  def sparse_symbol_grammar
    symbols = [
      Ibex::IR::GrammarSymbol.new(id: 0, name: "$eof", kind: :terminal, reserved: true),
      Ibex::IR::GrammarSymbol.new(id: 1, name: "error", kind: :terminal, reserved: true),
      Ibex::IR::GrammarSymbol.new(id: 7, name: "LOW", kind: :terminal),
      Ibex::IR::GrammarSymbol.new(id: 101, name: "HIGH", kind: :terminal),
      Ibex::IR::GrammarSymbol.new(id: 103, name: "start", kind: :nonterminal)
    ]
    productions = [
      production(id: 0, lhs: 103, rhs: [101]),
      production(id: 1, lhs: 103, rhs: [101, 7]),
      production(id: 2, lhs: 103, rhs: [7])
    ]
    Ibex::IR::Grammar.new(
      class_name: "Sparse", superclass: nil, start: "start", expect: 0, options: {},
      symbols: symbols, productions: productions, user_code: {}, conversions: {}, warnings: []
    )
  end

  def production(id:, lhs:, rhs:)
    Ibex::IR::Production.new(
      id: id, lhs: lhs, rhs: rhs, action: nil, precedence_override: nil,
      origin: { kind: :rule }
    )
  end

  def legacy_lr0_collection(lookaheads)
    seed = Set[lookaheads.send(:item_core, -1, 0)]
    states = [lookaheads.send(:closure, seed)]
    transitions = []
    indexes = { states.first.to_a.sort => 0 }
    cursor = 0
    while cursor < states.length
      transitions[cursor] = {}
      legacy_next_symbols(lookaheads, states.fetch(cursor)).each do |symbol_id|
        target = legacy_go_to(lookaheads, states.fetch(cursor), symbol_id)
        key = target.to_a.sort
        target_id = indexes[key] ||= begin
          states << target
          states.length - 1
        end
        transitions.fetch(cursor)[symbol_id] = target_id
      end
      cursor += 1
    end
    [states, transitions]
  end

  def legacy_next_symbols(lookaheads, items)
    items.filter_map do |production_id, dot|
      lookaheads.send(:rhs_for, production_id)[dot]
    end.uniq.sort
  end

  def legacy_go_to(lookaheads, items, symbol_id)
    moved = items.filter_map do |production_id, dot|
      next unless lookaheads.send(:rhs_for, production_id)[dot] == symbol_id

      lookaheads.send(:item_core, production_id, dot + 1)
    end
    lookaheads.send(:closure, Set.new(moved))
  end

  def normalize(source, mode: :default)
    ast = Ibex::Frontend::Parser.new(source, file: "direct-lookaheads.y", mode: mode).parse
    Ibex::Normalizer.new(ast, mode: mode).normalize
  end

  def measure_allocations(iterations, &operation)
    GC.start
    before = GC.stat(:total_allocated_objects)
    iterations.times(&operation)
    GC.stat(:total_allocated_objects) - before
  end
end
# rubocop:enable Metrics/ClassLength
