# frozen_string_literal: true

require_relative "../test_helper"

class DirectLookaheadsTest < Minitest::Test
  Terminal = Struct.new(:id, keyword_init: true)
  StartSymbol = Struct.new(:id, keyword_init: true)
  Grammar = Struct.new(:terminals, :productions, :start, :start_symbol, keyword_init: true) do
    def symbol(name)
      start_symbol if name == start
    end
  end

  def test_terminal_id_lookup_reuses_large_bit_masks
    iterations = 500
    ids = [100, 101, 102]
    lookaheads = direct_lookaheads(ids)
    bits = ids.sum { |id| 1 << id }

    assert_equal ids, lookaheads.send(:terminal_ids, bits)
    assert_equal [100, 102], lookaheads.send(:terminal_ids, (1 << 102) | (1 << 100))
    cached_allocations = measure_allocations(iterations) { lookaheads.send(:terminal_ids, bits) }
    shifted_allocations = measure_allocations(iterations) do
      ids.select { |id| bits.anybits?(1 << id) }
    end

    assert_operator cached_allocations, :<, shifted_allocations * 0.8
  end

  def test_rhs_and_initial_item_cores_are_reused
    grammar = normalize(<<~GRAMMAR)
      class P
      token ITEM
      rule
      start: list
      list: list ITEM |
      end
    GRAMMAR
    lookaheads = Ibex::LALR::DirectLookaheads.new(grammar, Ibex::Analysis::Sets.new(grammar))

    assert_same lookaheads.send(:rhs_for, -1), lookaheads.send(:rhs_for, -1)
    grammar.productions.each do |production|
      assert_same production.rhs, lookaheads.send(:rhs_for, production.id)
    end

    first = lookaheads.send(:closure, Set[[-1, 0]])
    second = lookaheads.send(:closure, Set[[-1, 0]])
    grammar.productions.each do |production|
      first_core = first.find { |production_id, dot| production_id == production.id && dot.zero? }
      second_core = second.find { |production_id, dot| production_id == production.id && dot.zero? }
      next unless first_core

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

  def normalize(source)
    Ibex::Normalizer.new(Ibex::Frontend::Parser.new(source, file: "direct-lookaheads.y").parse).normalize
  end

  def measure_allocations(iterations, &operation)
    GC.start
    before = GC.stat(:total_allocated_objects)
    iterations.times(&operation)
    GC.stat(:total_allocated_objects) - before
  end
end
