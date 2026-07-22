# frozen_string_literal: true

require_relative "../test_helper"

class AnalysisSetsTest < Minitest::Test
  def grammar(source)
    ast = Ibex::Frontend::Parser.new(source, file: "sets.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def test_dragon_book_cc_grammar
    sets = Ibex::Analysis::Sets.new(grammar(<<~GRAMMAR))
      class P
      rule
      start: pair pair
      pair: 'c' pair | 'd'
      end
    GRAMMAR
    refute sets.nullable?("start")
    assert_equal ["'c'", "'d'"], sets.first("start")
    assert_equal ["'c'", "'d'"], sets.first("pair")
    assert_equal ["$eof"], sets.follow("start")
    assert_equal ["$eof", "'c'", "'d'"], sets.follow("pair")
  end

  def test_empty_and_recursive_productions
    sets = Ibex::Analysis::Sets.new(grammar(<<~GRAMMAR))
      class P
      rule
      start: left right
      left: 'a' left |
      right: right 'b' |
      end
    GRAMMAR
    assert sets.nullable?("start")
    assert sets.nullable?("left")
    assert sets.nullable?("right")
    assert_equal ["'a'", "'b'"], sets.first("start")
    assert_equal ["$eof", "'b'"], sets.follow("left")
    assert_equal ["$eof", "'b'"], sets.follow("right")
  end

  def test_first_of_sequence_uses_bitsets
    parsed = grammar("class P\nrule\nstart: maybe 'z'\nmaybe: 'x' |\nend\n")
    sets = Ibex::Analysis::Sets.new(parsed)
    ids = [parsed.symbol("maybe").id, parsed.symbol("'z'").id]
    bits = sets.first_of_sequence(ids)
    names = parsed.terminals.filter_map { |terminal| terminal.name if bits.anybits?(1 << terminal.id) }
    assert_equal ["'z'", "'x'"], names
  end

  def test_handles_a_thousand_productions_within_target
    rules = (0...1000).map do |index|
      rhs = index == 999 ? "'end'" : "n#{index + 1}"
      "n#{index}: #{rhs}"
    end
    parsed = grammar("class P\nrule\n#{rules.join("\n")}\nend\n")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sets = Ibex::Analysis::Sets.new(parsed)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_equal ["'end'"], sets.first("n0")
    assert_operator elapsed, :<, 1.0
  end
end
