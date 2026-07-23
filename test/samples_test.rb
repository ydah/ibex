# frozen_string_literal: true

require_relative "test_helper"

class SamplesTest < Minitest::Test
  def test_generates_deterministic_bounded_terminal_sentences
    grammar = normalize(<<~GRAMMAR)
      class Lists
      token ITEM COMMA
      rule
      start: items
      items: ITEM
           | ITEM COMMA items
      end
    GRAMMAR

    first = Ibex::Samples.new(grammar, seed: 12, max_tokens: 7).generate(count: 8)
    second = Ibex::Samples.new(grammar, seed: 12, max_tokens: 7).generate(count: 8)

    assert_equal first, second
    assert(first.all? { |sample| sample.length <= 7 })
    assert(first.all? { |sample| sample.each_slice(2).all? { |item, comma| item == "ITEM" && comma != "ITEM" } })
    assert_operator first.map(&:length).uniq.length, :>, 1
  end

  def test_empty_productions_generate_an_empty_sentence
    grammar = normalize("class Empty\nrule\nstart:\nend\n")

    assert_equal [[]], Ibex::Samples.new(grammar).generate
  end

  def test_does_not_generate_the_synthetic_error_terminal
    grammar = normalize(<<~GRAMMAR)
      class Recovering
      token ITEM
      rule
      start: ITEM | error
      end
    GRAMMAR

    samples = Ibex::Samples.new(grammar, seed: 4).generate(count: 20)
    assert_equal [["ITEM"]], samples.uniq
  end

  def test_rejects_an_empty_language_and_too_small_budget
    empty_language = normalize("class Loop\nrule\nstart: start\nend\n")
    error = assert_raises(Ibex::Error) { Ibex::Samples.new(empty_language).generate }
    assert_match(/derives no terminal sentence/, error.message)

    grammar = normalize("class Pair\nrule\nstart: A B\nend\n")
    error = assert_raises(Ibex::Error) { Ibex::Samples.new(grammar, max_tokens: 1).generate }
    assert_match(/minimum sentence needs 2 tokens/, error.message)
  end

  def test_expands_a_deep_finite_grammar_without_using_the_ruby_call_stack
    grammar = chain_grammar(2_000)

    assert_equal [["TOKEN"]], Ibex::Samples.new(grammar, max_tokens: 1).generate
  end

  def test_reports_an_exact_minimum_for_a_huge_finite_sentence
    levels = 1_100
    grammar = binary_chain_grammar(levels)

    error = assert_raises(Ibex::Error) { Ibex::Samples.new(grammar, max_tokens: 1).generate }
    assert_match(/minimum sentence needs #{1 << levels} tokens/, error.message)
  end

  def test_bounds_total_expansion_work
    grammar = chain_grammar(2_000)
    generator = Ibex::Samples.new(grammar, max_tokens: 1, max_expansions: 1_000)

    error = assert_raises(Ibex::Error) { generator.generate }
    assert_match(/\A\(samples\):1:1: expansion limit of 1000 steps exceeded\z/, error.message)
  end

  def test_rejects_a_count_that_cannot_fit_the_expansion_limit
    grammar = normalize("class Empty\nrule\nstart:\nend\n")
    generator = Ibex::Samples.new(grammar, max_expansions: 2)

    error = assert_raises(Ibex::Error) { generator.generate(count: 3) }
    assert_match(/\A\(samples\):1:1: count 3 exceeds expansion limit 2\z/, error.message)
  end

  private

  def normalize(source)
    Ibex::Normalizer.new(Ibex::Frontend::Parser.new(source, file: "samples.y").parse).normalize
  end

  def chain_grammar(levels)
    grammar_from_rhs(levels) do |index, nonterminal_ids, terminal_id|
      [index == levels - 1 ? terminal_id : nonterminal_ids.fetch(index + 1)]
    end
  end

  def binary_chain_grammar(levels)
    grammar_from_rhs(levels) do |index, nonterminal_ids, terminal_id|
      child = index == levels - 1 ? terminal_id : nonterminal_ids.fetch(index + 1)
      [child, child]
    end
  end

  def grammar_from_rhs(levels)
    symbols, nonterminal_ids = grammar_symbols(levels)
    productions = nonterminal_ids.each_with_index.map do |lhs, index|
      Ibex::IR::Production.new(
        id: index,
        lhs: lhs,
        rhs: yield(index, nonterminal_ids, 2),
        action: nil,
        precedence_override: nil,
        origin: { kind: :rule }
      )
    end
    Ibex::IR::Grammar.new(
      class_name: "Deep",
      superclass: nil,
      start: "n0",
      expect: 0,
      options: {},
      symbols: symbols,
      productions: productions,
      user_code: {},
      conversions: {},
      warnings: []
    )
  end

  def grammar_symbols(levels)
    symbols = [
      Ibex::IR::GrammarSymbol.new(id: 0, name: "$eof", kind: :terminal, reserved: true),
      Ibex::IR::GrammarSymbol.new(id: 1, name: "error", kind: :terminal, reserved: true),
      Ibex::IR::GrammarSymbol.new(id: 2, name: "TOKEN", kind: :terminal)
    ]
    ids = Array.new(levels) do |index|
      id = index + symbols.length
      symbols << Ibex::IR::GrammarSymbol.new(id: id, name: "n#{index}", kind: :nonterminal)
      id
    end
    [symbols, ids]
  end
end
