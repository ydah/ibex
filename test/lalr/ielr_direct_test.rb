# frozen_string_literal: true

require_relative "../test_helper"

class IELRDirectTest < Minitest::Test
  FIXTURES = Dir.glob(File.expand_path("../fixtures/ielr/*.y", __dir__)).freeze

  def grammar(source)
    ast = Ibex::Frontend::Parser.new(source, file: "ielr.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def test_digraph_closes_sccs_and_dags
    assert_equal [7, 7, 4, 0], Ibex::Analysis::Digraph.closure([1, 2, 4, 0], [[1], [0, 2], [3], []])
  end

  def test_direct_ielr_preserves_canonical_actions
    source = <<~GRAMMAR
      class P
      preclow
      left 'a'
      prechigh
      rule
      s: 'a' x 'a' | 'b' x 'b'
      x: 'a' | 'a' 'a'
      end
    GRAMMAR
    grammar = grammar(source)
    builder = Ibex::LALR::Builder.new(grammar, algorithm: :ielr, ielr_strategy: :direct, profile: true)
    direct = builder.build

    assert(direct.states.any? { |state| state.conflicts.any? })
    assert_equal :ielr_direct, builder.metrics.strategy
    assert_nil builder.metrics.canonical_states
    assert_operator builder.metrics.ielr_split_states, :>=, 1
  end

  def test_goto_follow_reductions_match_direct_propagation
    grammar = grammar(<<~GRAMMAR)
      class P
      rule
      start: pair pair
      pair: 'c' pair | 'd'
      end
    GRAMMAR
    sets = Ibex::Analysis::Sets.new(grammar)
    direct = Ibex::LALR::DirectLookaheads.new(grammar, sets, profile: true)
    direct_items, transitions = direct.build
    follows = Ibex::LALR::GotoFollows.new(grammar, sets, direct.states, transitions, [0])
    expected = direct_items.each_with_index.map do |items, _state_id|
      items.each_with_object({}) do |((production_id, dot), lookaheads), result|
        next unless dot == (production_id.negative? ? 1 : grammar.productions.fetch(production_id).rhs.length)

        result[production_id] = lookaheads.reduce(0) { |bits, token| bits | (1 << token) }
      end
    end

    assert_equal expected, follows.reduction_lookaheads
    follows.always_follows.each_with_index do |bits, index|
      assert_equal bits, bits & follows.goto_follows.fetch(index)
    end
  end

  def test_paper_fixtures_build_without_canonical_collection
    assert_equal 6, FIXTURES.length

    FIXTURES.each do |path|
      grammar = Ibex::Normalizer.new(
        Ibex::Frontend::Parser.new(File.binread(path), file: path).parse
      ).normalize
      builder = Ibex::LALR::Builder.new(
        grammar, algorithm: :ielr, ielr_strategy: :direct, profile: true
      )
      builder.define_singleton_method(:canonical_collection) do
        raise "direct IELR unexpectedly requested canonical LR(1)"
      end

      automaton = builder.build
      assert_equal :ielr_direct, builder.metrics.strategy, path
      assert_nil builder.metrics.canonical_states, path
      assert_operator automaton.states.length, :>=, builder.metrics.ielr_lalr_states, path
    end
  end

  def test_direct_and_partition_preserve_fixture_conflict_summaries
    FIXTURES.each do |path|
      grammar = Ibex::Normalizer.new(
        Ibex::Frontend::Parser.new(File.binread(path), file: path).parse
      ).normalize
      direct = Ibex::LALR::Builder.new(
        grammar, algorithm: :ielr, ielr_strategy: :direct
      ).build
      partition = Ibex::LALR::Builder.new(
        grammar, algorithm: :ielr, ielr_strategy: :partition
      ).build

      assert_equal partition.conflict_summary, direct.conflict_summary, path
    end
  end

  def test_direct_ielr_acceptance_matrix_matches_canonical_behavior
    cases = {
      "fig1.y" => ["'b'", "'a'", "'a'", "'b'"],
      "fig2.y" => ["'a'", "'a'", "'a'", "'b'"],
      "fig3.y" => ["'b'", "'a'", "'a'", "'a'"],
      "fig4.y" => ["'b'", "'a'", "'b'"]
    }
    cases.each do |name, tokens|
      path = File.expand_path("../fixtures/ielr/#{name}", __dir__)
      grammar = Ibex::Normalizer.new(
        Ibex::Frontend::Parser.new(File.binread(path), file: path).parse
      ).normalize
      direct = Ibex::LALR::Builder.new(
        grammar, algorithm: :ielr, ielr_strategy: :direct
      ).build
      lalr = Ibex::LALR::Builder.new(grammar, algorithm: :lalr).build

      assert_equal :accepted, Ibex::TableSimulation::Simulator.new(direct).simulate(tokens).status, name
      assert_equal :error, Ibex::TableSimulation::Simulator.new(lalr).simulate(tokens).status, name
    end
  end
end
