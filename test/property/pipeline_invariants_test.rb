# frozen_string_literal: true

require_relative "../test_helper"

class PipelineInvariantsTest < Minitest::Test
  PROPERTY_SEEDS = [1009, 2027, 4093, 8191, 16_381].freeze
  ALGORITHMS = %i[slr lalr lr1].freeze

  def test_seeded_grammars_preserve_pipeline_invariants
    PROPERTY_SEEDS.each do |seed|
      source = grammar_source(seed)
      grammar = normalize(source, seed)
      assert_equal serialize(grammar), serialize(normalize(source, seed)), "grammar seed #{seed} was not deterministic"

      ALGORITHMS.each do |algorithm|
        automaton = Ibex::LALR::Builder.new(grammar, algorithm: algorithm).build
        rebuilt = Ibex::LALR::Builder.new(grammar, algorithm: algorithm).build
        assert_equal serialize(automaton), serialize(rebuilt), "#{algorithm} seed #{seed} was not deterministic"
        assert_automaton_invariants(automaton, seed, algorithm)
        assert_table_equivalence(automaton, seed, algorithm)
      end
    end
  end

  private

  def grammar_source(seed)
    random = Random.new(seed)
    depth = random.rand(2..4)
    tokens = Array.new((depth + 1) * 3) { |index| "TOKEN_#{index}" }.shuffle(random: random)
    rules = Array.new(depth) do |index|
      next_rule = "node_#{index + 1}"
      alternatives = alternatives_for(random, tokens.slice(index * 3, 3), "node_#{index}", next_rule)
      "node_#{index}: #{alternatives}"
    end
    tail = tokens.slice(depth * 3, 3).join(" | ")
    <<~GRAMMAR
      class SeededParser#{seed}
      token #{tokens.join(' ')}
      rule
      start: node_0
      #{rules.join("\n")}
      node_#{depth}: #{tail}
      end
    GRAMMAR
  end

  def alternatives_for(random, tokens, current_rule, next_rule)
    case random.rand(3)
    when 0 then "#{tokens[0]} #{next_rule} | #{tokens[1]} | #{tokens[2]}"
    when 1 then "#{tokens[0]} #{current_rule} | #{next_rule}"
    else "#{tokens[0]} #{next_rule} | #{tokens[1]} #{next_rule} | #{tokens[2]}"
    end
  end

  def normalize(source, seed)
    ast = Ibex::Frontend::Parser.new(source, file: "seed-#{seed}.y").parse
    Ibex::Normalizer.new(ast).normalize
  end

  def serialize(value)
    Ibex::IR::Serialize.dump(value)
  end

  def assert_automaton_invariants(automaton, seed, algorithm)
    grammar = automaton.grammar
    state_ids = automaton.states.map(&:id)
    assert_equal Array.new(automaton.states.length, &:itself), state_ids, context(seed, algorithm, "state ids")
    automaton.states.each do |state|
      assert_items(grammar, state, seed, algorithm)
      assert_transitions(grammar, state_ids, state, seed, algorithm)
      assert_actions(grammar, state_ids, state, seed, algorithm)
    end
    assert automaton.states.any? { |state| state.actions.values.any? { |action| action[:type] == :accept } },
           context(seed, algorithm, "missing accept action")
  end

  def assert_items(grammar, state, seed, algorithm)
    state.items.each do |item|
      rhs_length = item.production == -1 ? 1 : grammar.productions.fetch(item.production).rhs.length
      assert item.dot.between?(0, rhs_length), context(seed, algorithm, "invalid item dot in state #{state.id}")
      assert_equal item.lookaheads.sort.uniq, item.lookaheads,
                   context(seed, algorithm, "invalid lookaheads in state #{state.id}")
      item.lookaheads.each do |symbol_id|
        assert grammar.symbol_by_id(symbol_id)&.terminal?,
               context(seed, algorithm, "nonterminal lookahead in state #{state.id}")
      end
    end
  end

  def assert_transitions(grammar, state_ids, state, seed, algorithm)
    state.transitions.each do |symbol_id, target|
      symbol = grammar.symbol_by_id(symbol_id)
      assert symbol, context(seed, algorithm, "unknown transition symbol in state #{state.id}")
      assert_includes state_ids, target, context(seed, algorithm, "unknown transition target in state #{state.id}")
      expected = symbol.terminal? ? { type: :shift, state: target } : target
      actual = symbol.terminal? ? state.actions[symbol_id] : state.gotos[symbol_id]
      assert_equal expected, actual, context(seed, algorithm, "transition mismatch in state #{state.id}")
    end
  end

  def assert_actions(grammar, state_ids, state, seed, algorithm)
    state.gotos.each_key do |symbol_id|
      assert grammar.symbol_by_id(symbol_id)&.nonterminal?, context(seed, algorithm, "terminal in goto row")
    end
    state.actions.each do |symbol_id, action|
      assert grammar.symbol_by_id(symbol_id)&.terminal?, context(seed, algorithm, "nonterminal in action row")
      case action.fetch(:type)
      when :shift then assert_includes state_ids, action.fetch(:state), context(seed, algorithm, "bad shift")
      when :reduce then assert grammar.productions[action.fetch(:production)], context(seed, algorithm, "bad reduction")
      when :accept, :error then assert true
      else flunk context(seed, algorithm, "unknown action #{action.inspect}")
      end
    end
  end

  def assert_table_equivalence(automaton, seed, algorithm)
    plain = Ibex::Tables.build(automaton, format: :plain)
    compact = Ibex::Tables.build(automaton, format: :compact)
    automaton.states.each do |state|
      message = context(seed, algorithm, "table row #{state.id}")
      assert_equal plain.actions.fetch(state.id), compact.actions.row(state.id), message
      assert_equal plain.gotos.fetch(state.id), compact.gotos.row(state.id), message
      assert_optional_equal(plain.default_actions.fetch(state.id), compact.default_actions.fetch(state.id), message)
    end
  end

  def assert_optional_equal(expected, actual, message)
    expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
  end

  def context(seed, algorithm, detail)
    "#{detail} (seed=#{seed}, algorithm=#{algorithm})"
  end
end
