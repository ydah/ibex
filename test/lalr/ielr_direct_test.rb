# frozen_string_literal: true

require_relative "../test_helper"

# rubocop:disable Metrics/ClassLength -- direct IELR phase gates share one fixture/reference harness.
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

  def test_fig5_table_four_follow_sets_and_dependency_kinds
    grammar, states, follows = goto_follows_for("fig5.y")

    assert_equal 18, states.length
    assert_equal ["'a'", "'c'"], follow_names(grammar, follows, 1, "x")
    assert_equal ["'b'", "'c'"], follow_names(grammar, follows, 3, "x")
    assert_equal ["'a'"], follow_names(grammar, follows, 4, "z")
    assert_equal ["'a'"], follow_names(grammar, follows, 4, "d")
    assert_equal ["'a'"], follow_names(grammar, follows, 5, "y")
    assert_equal ["'b'"], follow_names(grammar, follows, 6, "y")
    assert_equal ["'a'", "'b'", "'c'"], follow_names(grammar, follows, 8, "d")
    assert_equal ["'a'", "'b'", "'c'"], follow_names(grammar, follows, 13, "e")

    assert_dependency_edges(grammar, follows, :successor, [[1, "x", 5, "y"],
                                                           [3, "x", 6, "y"],
                                                           [8, "d", 13, "e"]])
    assert_dependency_edges(grammar, follows, :internal, [[4, "d", 4, "z"]])
    assert_dependency_edges(grammar, follows, :includes, [[4, "d", 4, "z"],
                                                          [8, "d", 1, "x"],
                                                          [8, "d", 3, "x"],
                                                          [13, "e", 1, "x"],
                                                          [13, "e", 3, "x"]])
  end

  def test_fig6_table_six_preserves_lane_specific_follow_sets
    grammar, states, follows = goto_follows_for("fig6.y")

    assert_equal 14, states.length
    assert_equal ["'a'"], follow_names(grammar, follows, 2, "y")
    assert_equal ["'b'"], follow_names(grammar, follows, 3, "y")
    assert_equal ["'a'", "'b'"], follow_names(grammar, follows, 5, "z")
    assert_equal ["'a'", "'b'"], follow_names(grammar, follows, 5, "d")

    assert_dependency_edges(grammar, follows, :successor, [[2, "y", 5, "z"],
                                                           [2, "y", 5, "d"],
                                                           [3, "y", 5, "z"],
                                                           [3, "y", 5, "d"]])
    assert_dependency_edges(grammar, follows, :internal, [[2, "y", 2, "x"],
                                                          [3, "y", 3, "x"],
                                                          [5, "d", 5, "z"]])
    assert_dependency_edges(grammar, follows, :includes, [[2, "y", 2, "x"],
                                                          [3, "y", 3, "x"],
                                                          [5, "z", 2, "x"],
                                                          [5, "z", 3, "x"],
                                                          [5, "d", 5, "z"]])
  end

  def test_always_follows_matches_an_independent_fixed_point
    ["fig5.y", "fig6.y"].each do |name|
      _, _states, follows = goto_follows_for(name)
      expected = follows.direct_reads.dup
      loop do
        next_expected = expected.each_with_index.map do |bits, goto_id|
          edges = follows.successor_edges.fetch(goto_id) + follows.internal_edges.fetch(goto_id)
          edges.reduce(bits) do |value, target|
            value | expected.fetch(target)
          end
        end
        break if next_expected == expected

        expected = next_expected
      end

      assert_equal expected, follows.always_follows, name
      follows.always_follows.each_with_index do |bits, goto_id|
        assert_equal bits, bits & follows.goto_follows.fetch(goto_id), name
      end
    end
  end

  def test_goto_follows_match_direct_lalr_completed_lookaheads_for_every_gallery_grammar
    Dir.glob(File.expand_path("../../gallery/*/grammar.y", __dir__)).each do |path|
      grammar = Ibex::Normalizer.new(
        Ibex::Frontend::Parser.new(File.binread(path), file: path, mode: :extended).parse
      ).normalize
      sets = Ibex::Analysis::Sets.new(grammar)
      direct = Ibex::LALR::DirectLookaheads.new(grammar, sets, profile: true)
      direct_items, transitions = direct.build
      follows = Ibex::LALR::GotoFollows.new(grammar, sets, direct.states, transitions, [0])

      direct_items.each_with_index do |items, state_id|
        items.each do |(production_id, dot), lookaheads|
          next unless dot == rhs_length(grammar, production_id)

          expected = lookaheads.reduce(0) { |bits, token| bits | (1 << token) }
          assert_equal expected, follows.reduction_lookaheads.fetch(state_id).fetch(production_id), path
        end
      end
    end
  end

  def test_phase_four_without_a_split_matches_lalr_and_canonical_merge
    grammar = grammar(File.binread(File.expand_path("../fixtures/ielr/fig6.y", __dir__)))
    direct_lalr = Ibex::LALR::Builder.new(grammar, algorithm: :lalr).build
    canonical_merge = Ibex::LALR::Builder.new(
      grammar, algorithm: :lalr, lalr_strategy: :canonical_merge
    ).build
    direct_ielr_builder = Ibex::LALR::Builder.new(
      grammar, algorithm: :ielr, ielr_strategy: :direct, profile: true
    )
    direct_ielr = direct_ielr_builder.build

    assert_equal 0, direct_ielr_builder.metrics.ielr_split_states
    assert_equal automaton_signature(direct_lalr), automaton_signature(canonical_merge)
    assert_equal automaton_signature(direct_lalr), automaton_signature(direct_ielr)
  end

  def test_direct_state_count_is_bounded_and_deterministic_on_paper_fixtures
    FIXTURES.each do |path|
      grammar = Ibex::Normalizer.new(
        Ibex::Frontend::Parser.new(File.binread(path), file: path).parse
      ).normalize
      lalr = Ibex::LALR::Builder.new(grammar, algorithm: :lalr).build
      canonical = Ibex::LALR::Builder.new(grammar, algorithm: :lr1).build
      first = Ibex::LALR::Builder.new(
        grammar, algorithm: :ielr, ielr_strategy: :direct, profile: true
      )
      first_automaton = first.build
      second_automaton = Ibex::LALR::Builder.new(
        grammar, algorithm: :ielr, ielr_strategy: :direct
      ).build

      assert_operator first_automaton.states.length, :>=, lalr.states.length, path
      assert_operator first_automaton.states.length, :<=, canonical.states.length, path
      assert_equal automaton_signature(first_automaton), automaton_signature(second_automaton), path
    end
  end

  def test_direct_ielr_passes_strict_core_union_verification_on_paper_fixtures
    FIXTURES.each do |path|
      grammar = Ibex::Normalizer.new(
        Ibex::Frontend::Parser.new(File.binread(path), file: path).parse
      ).normalize
      automaton = Ibex::LALR::Builder.new(
        grammar, algorithm: :ielr, ielr_strategy: :direct
      ).build
      result = Ibex::Verify::Verifier.new(automaton, strict: true).verify

      assert_empty result.violations, path
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

  private

  def goto_follows_for(name)
    path = File.expand_path("../fixtures/ielr/#{name}", __dir__)
    grammar = Ibex::Normalizer.new(
      Ibex::Frontend::Parser.new(File.binread(path), file: path).parse
    ).normalize
    sets = Ibex::Analysis::Sets.new(grammar)
    states, transitions = Ibex::LALR::LR0Collection.new(grammar).build
    [grammar, states, Ibex::LALR::GotoFollows.new(grammar, sets, states, transitions, [0])]
  end

  def follow_names(grammar, follows, state_id, symbol_name)
    symbol_id = grammar.symbol(symbol_name).id
    goto_id = follows.goto_for(state_id, symbol_id)
    bits = follows.goto_follows.fetch(goto_id)
    grammar.terminals.filter_map { |terminal| terminal.name if bits.anybits?(1 << terminal.id) }
  end

  def assert_dependency_edges(grammar, follows, relation, expected)
    labels = follows.goto_index.each_with_object({}) do |((state_id, symbol_id), goto_id), result|
      result[goto_id] = [state_id, grammar.symbol_by_id(symbol_id).name]
    end
    actual = follows.public_send("#{relation}_edges").each_with_index.flat_map do |targets, goto_id|
      targets.map do |target|
        [*labels.fetch(goto_id), *labels.fetch(target)]
      end
    end.sort
    assert_equal expected.map(&:flatten).sort, actual
  end

  def rhs_length(grammar, production_id)
    production_id.negative? ? 1 : grammar.productions.fetch(production_id).rhs.length
  end

  def automaton_signature(automaton)
    automaton.states.map do |state|
      [state.items.map { |item| [item.production, item.dot, item.lookaheads] }.sort,
       state.transitions, state.actions, state.gotos, state.default_action, state.conflicts]
    end
  end
end

# rubocop:enable Metrics/ClassLength
