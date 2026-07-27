# frozen_string_literal: true

require_relative "../test_helper"

class CanonicalSuffixCacheTest < Minitest::Test
  class UncachedBuilder < Ibex::LALR::Builder
    private

    def canonical_suffix_lookaheads(production_id, dot, inherited)
      suffix_lookaheads(rhs_for(production_id).drop(dot + 1), inherited)
    end
  end

  CANONICAL_CONFIGURATIONS = [
    { algorithm: :lr1 },
    { algorithm: :ielr },
    { algorithm: :lalr, lalr_strategy: :canonical_merge }
  ].freeze

  def test_cache_preserves_terminal_order_and_reuses_a_frozen_result_without_lookup_allocations
    grammar, builder, production = sparse_lookahead_subject
    inherited = grammar.symbol("TOKEN_79").id
    first = grammar.symbol("TOKEN_75").id

    result = builder.send(:canonical_suffix_lookaheads, production.id, 0, inherited)
    repeated = builder.send(:canonical_suffix_lookaheads, production.id, 0, inherited)

    assert_equal [first, inherited], result
    assert_same result, repeated
    assert_predicate result, :frozen?
    assert_raises(FrozenError) { result << grammar.symbol("TOKEN_73").id }
    assert_cache_shape(builder, production.id, inherited)
  end

  def test_cache_hits_avoid_per_lookup_allocations
    skip "runtime allocation counter unavailable" unless TestRuntimeCapabilities.allocation_counter?

    grammar, builder, production = sparse_lookahead_subject
    inherited = grammar.symbol("TOKEN_79").id
    builder.send(:canonical_suffix_lookaheads, production.id, 0, inherited)

    assert_allocation_free_cache_hits(builder, production.id, inherited)
  end

  def test_direct_lalr_does_not_populate_the_canonical_cache
    grammar = normalize(<<~GRAMMAR)
      class DirectParser
      rule
      start: list
      list: list ITEM | ITEM
      end
    GRAMMAR
    builder = Ibex::LALR::Builder.new(grammar)

    builder.build

    assert_empty builder.instance_variable_get(:@canonical_suffix_lookahead_cache)
  end

  def test_nullable_recursive_grammar_matches_the_uncached_reference_for_every_canonical_consumer
    grammar = normalize(<<~GRAMMAR)
      class NullableRecursive
      token OPEN CLOSE ITEM COMMA HIGH_0 HIGH_1 HIGH_2 HIGH_3 HIGH_4 HIGH_5 HIGH_6 HIGH_7 HIGH_8 HIGH_9
      rule
      start: OPEN values CLOSE | HIGH_9 values
      values: values COMMA value | value |
      value: ITEM | OPEN values CLOSE
      end
    GRAMMAR

    CANONICAL_CONFIGURATIONS.each do |options|
      assert_reference_equivalence(grammar, **options)
    end
  end

  def test_multiple_entries_and_entry_isolation_match_the_uncached_reference
    grammar = normalize(<<~GRAMMAR, mode: :extended)
      class MultipleEntries
      pragma extended
      start program expression
      token A B C
      rule
      program: sequence B
      expression: sequence C
      sequence: sequence A |
      end
    GRAMMAR

    CANONICAL_CONFIGURATIONS.each do |options|
      assert_reference_equivalence(grammar, **options)
      assert_reference_equivalence(grammar, **options, entry_isolation: true)
    end
  end

  def test_randomized_canonical_automata_and_generated_ruby_match_the_uncached_reference
    20.times do |seed|
      grammar = normalize(random_grammar(seed))
      CANONICAL_CONFIGURATIONS.each do |options|
        assert_reference_equivalence(grammar, **options)
      end
    end
  end

  def test_invalid_productions_and_missing_symbols_retain_uncached_failure_behavior
    grammar = normalize(<<~GRAMMAR)
      class InvalidReference
      rule
      start: ITEM
      end
    GRAMMAR
    builder = Ibex::LALR::Builder.new(grammar, algorithm: :lr1)
    reference = UncachedBuilder.new(grammar, algorithm: :lr1)

    assert_same_failure(
      -> { reference.send(:canonical_suffix_lookaheads, 99, 0, 0) },
      -> { builder.send(:canonical_suffix_lookaheads, 99, 0, 0) }
    )
    assert_same_failure(
      -> { reference.send(:canonical_suffix_lookaheads, -99, 0, 0) },
      -> { builder.send(:canonical_suffix_lookaheads, -99, 0, 0) }
    )

    invalid = grammar.dup
    production = grammar.productions.fetch(0)
    invalid_production = Ibex::IR::Production.new(
      id: production.id, lhs: production.lhs, rhs: [999], action: production.action,
      precedence_override: production.precedence_override, origin: production.origin
    )
    invalid.instance_variable_set(:@productions, [invalid_production].freeze)
    assert_same_failure(
      -> { UncachedBuilder.new(invalid, algorithm: :lr1) },
      -> { Ibex::LALR::Builder.new(invalid, algorithm: :lr1) }
    )
  end

  private

  def sparse_lookahead_subject
    token_names = Array.new(80) { |index| "TOKEN_#{index}" }
    grammar = normalize(<<~GRAMMAR)
      class SparseLookaheads
      token #{token_names.join(' ')}
      rule
      start: prefix suffix
      prefix: prefix TOKEN_1 |
      suffix: TOKEN_75 |
      end
    GRAMMAR
    builder = Ibex::LALR::Builder.new(grammar, algorithm: :lr1)
    production = grammar.productions.find { |candidate| candidate.lhs == grammar.symbol("start").id }
    [grammar, builder, production]
  end

  def assert_cache_shape(builder, production_id, inherited)
    cache = builder.instance_variable_get(:@canonical_suffix_lookahead_cache)
    assert_equal [production_id], cache.keys
    assert_equal [0], cache.fetch(production_id).keys
    assert_equal [inherited], cache.fetch(production_id).fetch(0).keys
  end

  def assert_allocation_free_cache_hits(builder, production_id, inherited)
    iterations = 1_000
    allocations = measure_allocations do
      iterations.times { builder.send(:canonical_suffix_lookaheads, production_id, 0, inherited) }
    end
    assert_operator allocations, :<, iterations / 10
  end

  def normalize(source, mode: :default)
    ast = Ibex::Frontend::Parser.new(source, file: "canonical-cache.y", mode: mode).parse
    Ibex::Normalizer.new(ast, mode: mode).normalize
  end

  def random_grammar(seed)
    random = Random.new(seed)
    tokens = Array.new(12) { |index| "TOKEN_#{index}" }
    branches = tokens.sample(6, random: random)
    <<~GRAMMAR
      class RandomCanonical#{seed}
      token #{tokens.join(' ')}
      rule
      start: sequence #{branches.fetch(0)} | nested #{branches.fetch(1)}
      sequence: sequence #{branches.fetch(2)} atom | atom |
      nested: #{branches.fetch(3)} sequence #{branches.fetch(4)} | sequence
      atom: #{branches.fetch(5)} | nested
      end
    GRAMMAR
  end

  def assert_reference_equivalence(grammar, **options)
    reference = UncachedBuilder.new(grammar, **options).build
    builder = Ibex::LALR::Builder.new(grammar, **options)
    actual = builder.build
    repeated = builder.build
    expected_ir = Ibex::IR::Serialize.dump(reference)
    actual_ir = Ibex::IR::Serialize.dump(actual)

    assert_equal expected_ir, actual_ir, options.inspect
    assert_equal actual_ir, Ibex::IR::Serialize.dump(repeated), "repeated #{options.inspect}"
    assert_equal generated_ruby(reference), generated_ruby(actual), options.inspect
  end

  def generated_ruby(automaton)
    Ibex::Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
  end

  def assert_same_failure(reference, cached)
    expected = assert_raises(StandardError, &reference)
    actual = assert_raises(expected.class, &cached)
    assert_equal expected.message, actual.message
  end

  def measure_allocations
    GC.start
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  end
end
