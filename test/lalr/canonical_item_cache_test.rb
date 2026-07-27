# frozen_string_literal: true

require "weakref"
require_relative "../test_helper"

# rubocop:disable Metrics/ClassLength -- canonical-construction invariants share reference builders and grammars.
class CanonicalItemCacheTest < Minitest::Test
  class AllocatingBuilder < Ibex::LALR::Builder
    private

    def canonical_collection
      states = @start_names.map do |name|
        closure(Set[canonical_item(augmented_production(name), 0, 0)])
      end
      transitions = []
      indexes = {}
      states.each_with_index { |items, index| indexes[item_key(items)] = index }
      cursor = 0
      while cursor < states.length
        transitions[cursor] = {}
        next_symbols(states.fetch(cursor)).each do |symbol_id|
          target = go_to(states.fetch(cursor), symbol_id)
          key = item_key(target)
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

    def canonical_item(production_id, dot, lookahead)
      [production_id, dot, lookahead]
    end

    def closure(seed)
      items = seed.dup
      queue = seed.to_a
      until queue.empty?
        production_id, dot, lookahead = queue.shift
        rhs = rhs_for(production_id)
        grammar_symbol = @grammar.symbol_by_id(rhs[dot])
        next unless grammar_symbol&.nonterminal?

        lookaheads = canonical_suffix_lookaheads(production_id, dot, lookahead)
        @productions_by_lhs.fetch(grammar_symbol.id, Array.new(0)).each do |production|
          lookaheads.each do |token_id|
            enqueue_item(items, queue, [production.id, 0, token_id])
          end
        end
      end
      items
    end

    def next_symbols(items)
      items.filter_map { |production_id, dot, _lookahead| rhs_for(production_id)[dot] }.uniq.sort
    end

    def go_to(items, symbol_id)
      moved = items.filter_map do |production_id, dot, lookahead|
        next unless rhs_for(production_id)[dot] == symbol_id

        [production_id, dot + 1, lookahead]
      end
      closure(Set.new(moved))
    end
  end

  class CountingBuilder < Ibex::LALR::Builder
    attr_reader :canonical_item_calls, :shifted_kernel_calls

    def initialize(...)
      super
      @canonical_item_calls = 0
      @shifted_kernel_calls = 0
    end

    private

    def canonical_item(...)
      @canonical_item_calls += 1
      super
    end

    def shifted_kernels(...)
      @shifted_kernel_calls += 1
      super
    end
  end

  class FailingBuilder < Ibex::LALR::Builder
    attr_reader :cached_items_before_failure

    private

    def canonical_collection
      super
      @cached_items_before_failure = count_cached_items
      raise "canonical construction failed"
    end

    def count_cached_items
      cache = instance_variable_get(:@canonical_item_cache)
      cache.sum do |_production, dots|
        dots.compact.sum { |lookaheads| lookaheads.compact.length }
      end
    end
  end

  class WeakItemBuilder < Ibex::LALR::Builder
    attr_reader :item_reference

    private

    def canonical_item(...)
      item = super
      @item_reference ||= WeakRef.new(item)
      item
    end
  end

  module FailingShiftClosure
    attr_reader :closure_signatures

    def initialize(...)
      @closure_signatures = []
      super
    end

    private

    def closure(seed)
      return super unless seed.any? { |_production, dot, _lookahead| dot.positive? }

      @closure_signatures << seed.to_a
      raise Ibex::Error, "shift closure failed"
    end
  end

  class GroupedFailureBuilder < Ibex::LALR::Builder
    include FailingShiftClosure
  end

  class AllocatingFailureBuilder < AllocatingBuilder
    include FailingShiftClosure
  end

  CANONICAL_CONFIGURATIONS = [
    { algorithm: :lr1 },
    { algorithm: :ielr },
    { algorithm: :lalr, lalr_strategy: :canonical_merge },
    { algorithm: :slr, lalr_strategy: :canonical_merge }
  ].freeze

  def test_lookup_is_lazy_nested_frozen_and_canonical
    grammar = normalize(nullable_recursive_grammar)
    builder = Ibex::LALR::Builder.new(grammar, algorithm: :lr1)

    assert_nil builder.instance_variable_get(:@canonical_item_cache)

    item = builder.send(:canonical_item, 3, 2, 17)
    repeated = builder.send(:canonical_item, 3, 2, 17)
    other = builder.send(:canonical_item, 3, 2, 19)

    assert_equal [3, 2, 17], item
    assert_same item, repeated
    refute_same item, other
    assert_predicate item, :frozen?
    assert_raises(FrozenError) { item << 23 }
    cache = builder.instance_variable_get(:@canonical_item_cache)
    items = cache.fetch(3).fetch(2)
    occupied = items.each_index.select { |index| items[index] }
    assert_equal [17, 19], occupied
    assert_same item, items.fetch(17)
  end

  def test_canonical_collection_reuses_items_and_preserves_oracle_insertion_order
    grammar = normalize(nullable_recursive_grammar)
    cached = Ibex::LALR::Builder.new(grammar, algorithm: :lr1)
    oracle = AllocatingBuilder.new(grammar, algorithm: :lr1)

    states, transitions = cached.send(:canonical_collection)
    oracle_states, oracle_transitions = oracle.send(:canonical_collection)

    assert_equal oracle_states.map(&:to_a), states.map(&:to_a)
    assert_equal oracle_transitions, transitions
    states.each do |items|
      items.each do |item|
        assert_predicate item, :frozen?
        assert_same cached.send(:canonical_item, *item), item
      end
    end
  end

  def test_shifted_kernels_preserve_filtered_item_order_and_deduplicate_equivalent_items
    grammar = sparse_symbol_grammar
    builder = Ibex::LALR::Builder.allocate
    builder.instance_variable_set(:@grammar, grammar)
    builder.instance_variable_set(:@canonical_item_cache, nil)
    first_high = builder.send(:canonical_item, 0, 0, 0)
    second_high = builder.send(:canonical_item, 1, 0, 0)
    completed = builder.send(:canonical_item, 0, 1, 0)
    items = [
      builder.send(:canonical_item, -1, 0, 0),
      first_high,
      second_high,
      second_high.dup,
      builder.send(:canonical_item, 2, 0, 0),
      completed
    ]

    kernels = builder.send(:shifted_kernels, items)

    assert_equal [103, 101, 7], kernels.keys
    assert_equal [[-1, 1, 0]], kernels.fetch(103).to_a
    assert_equal [[0, 1, 0], [1, 1, 0]], kernels.fetch(101).to_a
    assert_equal [[2, 1, 0]], kernels.fetch(7).to_a
    assert_empty builder.send(:shifted_kernels, Set.new)
    kernels.each_value do |kernel|
      kernel.each do |item|
        assert_predicate item, :frozen?
        assert_same builder.send(:canonical_item, *item), item
      end
    end
  end

  def test_canonical_transition_insertion_order_remains_sorted
    grammar = normalize(nullable_recursive_grammar)
    _states, transitions = Ibex::LALR::Builder.new(grammar, algorithm: :lr1).send(:canonical_collection)

    transitions.each { |edges| assert_equal edges.keys.sort, edges.keys }
  end

  def test_public_build_drops_items_but_preserves_other_canonical_caches_and_rebuilds_deterministically
    grammar = normalize(nullable_recursive_grammar)

    CANONICAL_CONFIGURATIONS.each do |options|
      builder = Ibex::LALR::Builder.new(grammar, **options)
      first = builder.build
      first_metrics = builder.metrics

      assert_nil builder.instance_variable_get(:@canonical_item_cache), options.inspect
      refute_empty builder.instance_variable_get(:@canonical_suffix_lookahead_cache), options.inspect
      refute_nil builder.instance_variable_get(:@canonical_key_radices), options.inspect

      second = builder.build

      assert_equal Ibex::IR::Serialize.dump(first), Ibex::IR::Serialize.dump(second), options.inspect
      assert_equal metrics_values(first_metrics), metrics_values(builder.metrics), options.inspect
      assert_nil builder.instance_variable_get(:@canonical_item_cache), options.inspect
    end
  end

  def test_public_build_releases_cached_items_while_the_builder_is_retained
    grammar = normalize(nullable_recursive_grammar)
    builder = WeakItemBuilder.new(grammar, algorithm: :lr1)

    builder.build
    reference = builder.item_reference
    assert reference
    assert_nil builder.instance_variable_get(:@canonical_item_cache)

    3.times { GC.start }

    refute_predicate reference, :weakref_alive?
    assert builder.metrics
  end

  def test_exception_drops_items_without_dropping_suffix_or_key_caches
    grammar = normalize(nullable_recursive_grammar)
    builder = FailingBuilder.new(grammar, algorithm: :lr1)

    error = assert_raises(RuntimeError) { builder.build }

    assert_equal "canonical construction failed", error.message
    assert_operator builder.cached_items_before_failure, :>, 0
    assert_nil builder.instance_variable_get(:@canonical_item_cache)
    refute_empty builder.instance_variable_get(:@canonical_suffix_lookahead_cache)
    refute_nil builder.instance_variable_get(:@canonical_key_radices)
    assert_nil builder.metrics
  end

  def test_grouped_collection_preserves_sorted_closure_exception_order_and_cache_cleanup
    grammar = normalize(nullable_recursive_grammar)
    grouped = GroupedFailureBuilder.new(grammar, algorithm: :lr1)
    oracle = AllocatingFailureBuilder.new(grammar, algorithm: :lr1)

    grouped_error = assert_raises(Ibex::Error) { grouped.build }
    oracle_error = assert_raises(Ibex::Error) { oracle.build }

    assert_equal [oracle_error.class, oracle_error.message], [grouped_error.class, grouped_error.message]
    assert_equal oracle.closure_signatures, grouped.closure_signatures
    assert_nil grouped.instance_variable_get(:@canonical_item_cache)
    assert_nil oracle.instance_variable_get(:@canonical_item_cache)
  end

  def test_direct_lalr_never_uses_or_populates_the_item_cache
    grammar = normalize(nullable_recursive_grammar)
    builder = CountingBuilder.new(grammar)

    builder.build

    assert_equal 0, builder.canonical_item_calls
    assert_equal 0, builder.shifted_kernel_calls
    assert_nil builder.instance_variable_get(:@canonical_item_cache)
  end

  def test_allocating_oracle_matches_for_multiple_entries_isolation_and_long_sparse_symbols
    grammars = [
      normalize(multiple_entry_grammar, mode: :extended),
      normalize(long_sparse_symbol_grammar)
    ]

    grammars.each do |grammar|
      assert_collection_equivalence(grammar)
      CANONICAL_CONFIGURATIONS.each do |options|
        assert_reference_equivalence(grammar, **options)
        assert_reference_equivalence(grammar, **options, entry_isolation: true) if grammar.starts.length > 1
      end
    end
  end

  def test_randomized_automata_and_compact_ruby_match_the_allocating_oracle
    12.times do |seed|
      grammar = normalize(random_grammar(seed))
      assert_collection_equivalence(grammar)
      CANONICAL_CONFIGURATIONS.each do |options|
        assert_reference_equivalence(grammar, **options)
      end
    end
  end

  private

  def assert_collection_equivalence(grammar)
    oracle_states, oracle_transitions = AllocatingBuilder.new(grammar, algorithm: :lr1).send(:canonical_collection)
    actual_states, actual_transitions = Ibex::LALR::Builder.new(grammar, algorithm: :lr1).send(:canonical_collection)

    assert_equal oracle_states.map(&:to_a), actual_states.map(&:to_a)
    assert_equal oracle_transitions, actual_transitions
  end

  def assert_reference_equivalence(grammar, **options)
    oracle = AllocatingBuilder.new(grammar, **options).build
    actual = Ibex::LALR::Builder.new(grammar, **options).build

    assert_equal oracle.to_h, actual.to_h, options.inspect
    assert_equal Ibex::IR::Serialize.dump(oracle), Ibex::IR::Serialize.dump(actual), options.inspect
    assert_equal generated_ruby(oracle), generated_ruby(actual), options.inspect
  end

  def generated_ruby(automaton)
    Ibex::Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
  end

  def metrics_values(metrics)
    [metrics.construction_states, metrics.canonical_states, metrics.final_states, metrics.strategy]
  end

  def normalize(source, mode: :racc)
    ast = Ibex::Frontend::Parser.new(source, file: "canonical-items.y", mode: mode).parse
    Ibex::Normalizer.new(ast, mode: mode).normalize
  end

  def nullable_recursive_grammar
    <<~GRAMMAR
      class NullableRecursiveItems
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
      class MultipleEntryItems
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

  def long_sparse_symbol_grammar
    tokens = Array.new(96) { |index| "TOKEN_#{index}" }
    rhs = Array.new(32) { |index| "TOKEN_#{(index * 29) % tokens.length}" }
    <<~GRAMMAR
      class LongSparseItems
      token #{tokens.join(' ')}
      rule
      start: sequence TOKEN_95 | TOKEN_91 sequence
      sequence: #{rhs.join(' ')} | sequence TOKEN_89 |
      end
    GRAMMAR
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
      class_name: "SparseItems", superclass: nil, start: "start", expect: 0, options: {},
      symbols: symbols, productions: productions, user_code: {}, conversions: {}, warnings: []
    )
  end

  def production(id:, lhs:, rhs:)
    Ibex::IR::Production.new(
      id: id, lhs: lhs, rhs: rhs, action: nil, precedence_override: nil, origin: { kind: :rule }
    )
  end

  def random_grammar(seed)
    random = Random.new(seed)
    tokens = Array.new(12) { |index| "TOKEN_#{index}" }
    selected = tokens.sample(8, random: random)
    <<~GRAMMAR
      class RandomItems#{seed}
      token #{tokens.join(' ')}
      rule
      start: sequence #{selected.fetch(0)} | nested #{selected.fetch(1)}
      sequence: sequence #{selected.fetch(2)} atom | atom |
      nested: #{selected.fetch(3)} sequence #{selected.fetch(4)} | sequence
      atom: #{selected.fetch(5)} | nested #{selected.fetch(6)} | #{selected.fetch(7)}
      end
    GRAMMAR
  end
end
# rubocop:enable Metrics/ClassLength
