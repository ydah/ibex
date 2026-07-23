# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Generates bounded terminal sentences from Grammar IR.
  class Samples
    DEFAULT_MAX_EXPANSIONS = 100_000 #: Integer

    # @rbs (IR::Grammar grammar, ?seed: Integer, ?max_tokens: Integer, ?max_depth: Integer,
    #   ?max_expansions: Integer) -> void
    def initialize(grammar, seed: 0, max_tokens: 32, max_depth: 16, max_expansions: DEFAULT_MAX_EXPANSIONS)
      raise ArgumentError, "max_tokens must be positive" unless max_tokens.positive?
      raise ArgumentError, "max_depth must be positive" unless max_depth.positive?
      raise ArgumentError, "max_expansions must be positive" unless max_expansions.positive?

      @grammar = grammar
      @random = Random.new(seed)
      @max_tokens = max_tokens
      @max_depth = max_depth
      @max_expansions = max_expansions
      @productions = grammar.productions.group_by(&:lhs)
      @minimum_costs = compute_minimum_costs
      @minimum_heights = compute_minimum_heights
    end

    # @rbs (?count: Integer) -> Array[Array[String]]
    def generate(count: 1)
      raise ArgumentError, "count must be positive" unless count.positive?

      start = @grammar.symbol(@grammar.start) || raise(Ibex::Error, "(samples):1:1: missing start symbol")
      minimum = @minimum_costs.fetch(start.id, nil)
      raise Ibex::Error, "(samples):1:1: start symbol #{@grammar.start} derives no terminal sentence" unless minimum

      if minimum > @max_tokens
        raise Ibex::Error, "(samples):1:1: minimum sentence needs #{minimum} tokens; limit is #{@max_tokens}"
      end
      if count > @max_expansions
        raise Ibex::Error, "(samples):1:1: count #{count} exceeds expansion limit #{@max_expansions}"
      end

      remaining_expansions = @max_expansions
      Array.new(count) do
        sample, remaining_expansions = expand(start, remaining_expansions)
        sample
      end
    end

    private

    # @rbs () -> Hash[Integer, Integer?]
    def compute_minimum_costs
      compute_minimum_values(1) do |production, values|
        rhs_values = resolved_rhs_values(production, values)
        rhs_values&.sum
      end
    end

    # @rbs () -> Hash[Integer, Integer?]
    def compute_minimum_heights
      compute_minimum_values(0) do |production, values|
        rhs_values = resolved_rhs_values(production, values)
        rhs_values && ((rhs_values.max || 0) + 1)
      end
    end

    # @rbs (Integer terminal_value) { (IR::Production, Hash[Integer, Integer?]) -> Integer? }
    #   -> Hash[Integer, Integer?]
    def compute_minimum_values(terminal_value)
      values = @grammar.symbols.to_h { |symbol| [symbol.id, nil] } #: Hash[Integer, Integer?]
      dependents = {} #: Hash[Integer, Array[IR::Production]]
      queue = seed_terminal_values(values, terminal_value)

      @grammar.productions.each do |production|
        update_minimum(values, queue, production.lhs, yield(production, values)) if production.rhs.empty?
        production.rhs.uniq.each do |symbol_id|
          (dependents[symbol_id] ||= []) << production
        end
      end

      index = 0
      while index < queue.length
        dependents.fetch(queue.fetch(index), []).each do |production|
          update_minimum(values, queue, production.lhs, yield(production, values))
        end
        index += 1
      end

      values
    end

    # @rbs (Hash[Integer, Integer?] values, Integer terminal_value) -> Array[Integer]
    def seed_terminal_values(values, terminal_value)
      @grammar.symbols.filter_map do |symbol|
        next unless symbol.terminal? && !symbol.reserved

        values[symbol.id] = terminal_value
        symbol.id
      end
    end

    # @rbs (Hash[Integer, Integer?] values, Array[Integer] queue, Integer symbol_id, Integer? candidate) -> void
    def update_minimum(values, queue, symbol_id, candidate)
      return unless candidate

      current = values.fetch(symbol_id)
      return if current && current <= candidate

      values[symbol_id] = candidate
      queue << symbol_id
    end

    # @rbs (IR::Production production, Hash[Integer, Integer?] values) -> Array[Integer]?
    def resolved_rhs_values(production, values)
      rhs_values = production.rhs.map { |symbol_id| values.fetch(symbol_id) }
      return nil if rhs_values.any?(&:nil?)

      rhs_values.compact
    end

    # @rbs (IR::GrammarSymbol start, Integer remaining_expansions) -> [Array[String], Integer]
    def expand(start, remaining_expansions)
      result = [] #: Array[String]
      work = [[start.id, 0]] #: Array[[Integer, Integer]]
      pending_minimum = minimum_cost!(start.id)

      while (entry = work.pop)
        if remaining_expansions.zero?
          raise Ibex::Error, "(samples):1:1: expansion limit of #{@max_expansions} steps exceeded"
        end

        remaining_expansions -= 1
        symbol_id, depth = entry
        pending_minimum -= minimum_cost!(symbol_id)
        symbol = @grammar.symbol_by_id(symbol_id) ||
                 raise(Ibex::Error, "(samples):1:1: missing symbol #{symbol_id}")
        if symbol.terminal?
          result << symbol.name
          next
        end

        budget = @max_tokens - result.length - pending_minimum
        production = choose_production(symbol_id, budget, depth)
        pending_minimum += production_cost(production) ||
                           raise(Ibex::Error, "(samples):1:1: no bounded derivation for symbol #{symbol_id}")
        production.rhs.reverse_each { |child_id| work << [child_id, depth + 1] }
      end

      [result, remaining_expansions]
    end

    # @rbs (Integer nonterminal_id, Integer budget, Integer depth) -> IR::Production
    def choose_production(nonterminal_id, budget, depth)
      productions = @productions[nonterminal_id]
      raise Ibex::Error, "(samples):1:1: no bounded derivation for symbol #{nonterminal_id}" unless productions

      candidates = productions.select do |production|
        cost = production_cost(production)
        cost && cost <= budget
      end
      raise Ibex::Error, "(samples):1:1: no bounded derivation for symbol #{nonterminal_id}" if candidates.empty?

      if depth >= @max_depth
        minimum = candidates.filter_map { |production| production_height(production) }.min
        candidates = candidates.select { |production| production_height(production) == minimum }
      end
      candidates.fetch(@random.rand(candidates.length))
    end

    # @rbs (Integer symbol_id) -> Integer
    def minimum_cost!(symbol_id)
      @minimum_costs.fetch(symbol_id) ||
        raise(Ibex::Error, "(samples):1:1: no bounded derivation for symbol #{symbol_id}")
    end

    # @rbs (IR::Production production) -> Integer?
    def production_cost(production)
      resolved_rhs_values(production, @minimum_costs)&.sum
    end

    # @rbs (IR::Production production) -> Integer?
    def production_height(production)
      child_heights = resolved_rhs_values(production, @minimum_heights)
      child_heights && ((child_heights.max || 0) + 1)
    end
  end
end
