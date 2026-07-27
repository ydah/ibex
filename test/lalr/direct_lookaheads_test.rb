# frozen_string_literal: true

require_relative "../test_helper"

class DirectLookaheadsTest < Minitest::Test
  Terminal = Struct.new(:id, keyword_init: true)
  Grammar = Struct.new(:terminals, :productions, keyword_init: true)

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

  private

  def direct_lookaheads(ids)
    grammar = Grammar.new(terminals: ids.map { |id| Terminal.new(id: id) }, productions: [])
    Ibex::LALR::DirectLookaheads.new(grammar, Object.new)
  end

  def measure_allocations(iterations, &operation)
    GC.start
    before = GC.stat(:total_allocated_objects)
    iterations.times(&operation)
    GC.stat(:total_allocated_objects) - before
  end
end
