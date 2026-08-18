# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # rubocop:disable Metrics/ClassLength -- the three comparison strategies share one report and budget contract.
  class Equiv
    require_relative "samples"
    require_relative "verify"
    require_relative "equiv/machine"

    # Bounded language comparison over two immutable parser automata.
    # @rbs!
    #   type tree_node_signature = [String, Array[String]]
    #   type tree_trace_entry = [String, Array[String], tree_node_signature?]
    #   type terminal_signature = [String, [Symbol, Integer]?]
    #   type production_signature = [String, Array[String], String?]

    CAVEAT = "Bounded search is not a proof of equivalence." #: String
    DEFAULT_MAX_ACTIONS = 100_000 #: Integer
    DEFAULT_MAX_STACK = 10_000 #: Integer

    class Difference < Ibex::Error
      attr_reader :details #: Hash[Symbol, Object?]

      # @rbs (Hash[Symbol, Object?] details) -> void
      def initialize(details)
        @details = IR.deep_freeze(details)
        label = details[:witness] ? " for #{details.fetch(:witness).inspect}" : ""
        super("(equiv):1:1: comparison found a difference#{label}")
      end
    end

    class BudgetExceeded < Ibex::Error
      attr_reader :details #: Hash[Symbol, Object?]

      # @rbs (Hash[Symbol, Object?] details) -> void
      def initialize(details)
        @details = IR.deep_freeze(details)
        super("(equiv):1:1: configured budget was exhausted")
      end
    end

    # @rbs (IR::Automaton left, IR::Automaton right, ?sample_count: Integer, ?seed: Integer,
    #   ?max_tokens: Integer, ?max_configurations: Integer, ?max_actions: Integer, ?max_stack: Integer,
    #   ?rule_map: Hash[String, String]) -> void
    def initialize(left, right, sample_count: 100, seed: 0, max_tokens: 8, max_configurations: 50_000,
                   max_actions: DEFAULT_MAX_ACTIONS, max_stack: DEFAULT_MAX_STACK, rule_map: {})
      budgets = {
        sample_count: sample_count, max_tokens: max_tokens, max_configurations: max_configurations,
        max_actions: max_actions, max_stack: max_stack
      }
      invalid = budgets.find { |_name, value| !value.positive? }
      raise ArgumentError, "#{invalid.fetch(0)} must be positive" if invalid

      @left = left
      @right = right
      @sample_count = sample_count
      @seed = seed
      @max_tokens = max_tokens
      @max_configurations = max_configurations
      @max_actions = max_actions
      @max_stack = max_stack
      @rule_map = rule_map.dup.freeze
      validate_rule_map!
      @left_machine = Machine.new(left, max_actions: max_actions, max_stack: max_stack)
      @right_machine = Machine.new(right, max_actions: max_actions, max_stack: max_stack)
    end

    # @rbs () -> Hash[Symbol, Object?]
    def run
      verify_inputs!
      structural = structural_identity?
      tree_structural = tree_structural_identity?
      return successful_report(structural: true, samples: 0, configurations: 0) if structural && tree_structural

      samples = compare_samples
      configurations = search_product
      successful_report(structural: false, samples: samples, configurations: configurations)
    rescue Machine::BudgetExceeded => e
      raise BudgetExceeded.new(
        result: "budget_exhausted", phase: "simulation", message: e.message,
        bounds: bounds, statement: CAVEAT
      )
    rescue Ibex::Error => e
      raise if e.is_a?(Difference) || e.is_a?(BudgetExceeded)
      raise unless sample_budget_error?(e)

      raise BudgetExceeded.new(
        result: "budget_exhausted", phase: "sampling", message: e.message,
        bounds: bounds, statement: CAVEAT
      )
    end

    private

    # @rbs () -> Integer
    def compare_samples
      left_samples = generated_samples(@left.grammar, @seed)
      right_samples = generated_samples(@right.grammar, @seed ^ 0x1BE)
      left_samples.each { |tokens| compare_tokens!(tokens, method: "left_to_right_sampling") }
      right_samples.each { |tokens| compare_tokens!(tokens, method: "right_to_left_sampling") }
      left_samples.length + right_samples.length
    end

    # @rbs (IR::Grammar grammar, Integer seed) -> Array[Array[String]]
    def generated_samples(grammar, seed)
      Samples.new(
        grammar, seed: seed, max_tokens: @max_tokens, max_depth: [@max_tokens * 2, 16].max,
                 max_expansions: [Samples::DEFAULT_MAX_EXPANSIONS, @sample_count * @max_tokens * 8].max,
                 strategy: :coverage, path_length: 2
      ).generate(count: @sample_count)
    end

    # @rbs () -> Integer
    def search_product # rubocop:disable Metrics/MethodLength -- BFS lifecycle remains visible as one bounded worklist.
      left_start = @left_machine.start
      right_start = @right_machine.start
      queue = [[left_start, right_start, []]] #: Array[[Machine::Configuration, Machine::Configuration, Array[String]]]
      seen = { product_key(left_start, right_start) => true }
      cursor = 0
      truncated = false
      alphabet = terminal_alphabet

      while cursor < queue.length
        left, right, tokens = queue.fetch(cursor)
        cursor += 1
        compare_configurations!(left, right, tokens)
        next if tokens.length >= @max_tokens || both_rejected?(left, right)

        alphabet.each do |token|
          next_left = @left_machine.push(left, token)
          next_right = @right_machine.push(right, token)
          key = product_key(next_left, next_right)
          next if seen[key]

          if queue.length >= @max_configurations
            truncated = true
            next
          end
          seen[key] = true
          queue << [next_left, next_right, tokens + [token]]
        end
      end
      if truncated
        raise BudgetExceeded.new(
          result: "budget_exhausted", phase: "product_bfs", checked_configurations: cursor,
          bounds: bounds, statement: CAVEAT
        )
      end

      cursor
    end

    # @rbs (Array[String] tokens, method: String) -> void
    def compare_tokens!(tokens, method:)
      left = @left_machine.finish(@left_machine.run(tokens))
      right = @right_machine.finish(@right_machine.run(tokens))
      compare_results!(left, right, tokens, method)
    end

    # @rbs (Machine::Configuration left, Machine::Configuration right, Array[String] tokens) -> void
    def compare_configurations!(left, right, tokens)
      left_result = @left_machine.finish(left)
      right_result = @right_machine.finish(right)
      compare_results!(left_result, right_result, tokens, "bounded_product_bfs")
    end

    # @rbs (Machine::Configuration left, Machine::Configuration right, Array[String] tokens, String method) -> void
    def compare_results!(left, right, tokens, method)
      raise_language_difference(tokens, left.status, right.status, method) unless left.status == right.status
      return unless left.status == :accepted && tree_requested?
      return if tree_trace(@left, left, map_left: true) == tree_trace(@right, right, map_left: false)

      raise Difference.new(
        ibex_report: "equiv", schema_version: 1, result: "difference",
        difference_kind: "tree", method: "#{method}_tree_trace", witness: tokens,
        outcomes: { left: left.status, right: right.status },
        bounds: bounds, statement: CAVEAT
      )
    end

    # @rbs (Array[String] tokens, Symbol? left, Symbol? right, String method) -> bot
    def raise_language_difference(tokens, left, right, method)
      raise Difference.new(
        ibex_report: "equiv", schema_version: 1, result: "difference",
        difference_kind: "language", method: method, witness: tokens, outcomes: { left: left, right: right },
        direction: left == :accepted ? "left_only" : "right_only",
        bounds: bounds, statement: CAVEAT
      )
    end

    # @rbs () -> bool
    def structural_identity?
      @left.algorithm == @right.algorithm &&
        grammar_signature(@left.grammar, map_left: true) == grammar_signature(@right.grammar, map_left: false)
    end

    # @rbs () -> bool
    def tree_structural_identity?
      return true unless tree_requested?

      tree_grammar_signature(@left.grammar) == tree_grammar_signature(@right.grammar)
    end

    # @rbs (IR::Grammar grammar) -> Array[tree_node_signature]
    def tree_grammar_signature(grammar)
      grammar.productions.filter_map { |production| node_signature(production.node) }
    end

    # @rbs (IR::node_annotation? node) -> tree_node_signature?
    def node_signature(node)
      node && [node.fetch(:name), node.fetch(:fields)]
    end

    # @rbs (IR::Automaton automaton, Machine::Configuration configuration, map_left: bool) -> Array[tree_trace_entry]
    def tree_trace(automaton, configuration, map_left:)
      configuration.reductions.map do |production_id|
        production = automaton.grammar.productions.fetch(production_id)
        lhs = symbol_name(automaton.grammar, production.lhs)
        [
          mapped_name(automaton.grammar, lhs, map_left: map_left),
          production.rhs.map do |id|
            mapped_name(automaton.grammar, symbol_name(automaton.grammar, id),
                        map_left: map_left)
          end,
          node_signature(production.node)
        ]
      end
    end

    # @rbs (IR::Grammar grammar, map_left: bool) -> Hash[Symbol, Object?]
    def grammar_signature(grammar, map_left:)
      {
        starts: grammar.starts.map { |name| mapped_name(grammar, name, map_left: map_left) },
        recovery: recovery_signature(grammar, map_left: map_left),
        terminals: terminal_signatures(grammar),
        productions: production_signatures(grammar, map_left: map_left)
      }
    end

    # @rbs (IR::Grammar grammar, map_left: bool) -> Hash[Symbol, Object?]
    def recovery_signature(grammar, map_left:)
      {
        sync_tokens: grammar.recovery.fetch(:sync_tokens),
        on_error_reduce: grammar.recovery.fetch(:on_error_reduce).map do |group|
          group.map { |name| mapped_name(grammar, name, map_left: map_left) }
        end
      }
    end

    # @rbs (IR::Grammar grammar) -> Array[terminal_signature]
    def terminal_signatures(grammar)
      grammar.terminals.map do |symbol|
        precedence = symbol.precedence
        [symbol.name, precedence && [precedence.fetch(:associativity), precedence.fetch(:level)]]
      end
    end

    # @rbs (IR::Grammar grammar, map_left: bool) -> Array[production_signature]
    def production_signatures(grammar, map_left:)
      grammar.productions.map { |production| production_signature(grammar, production, map_left: map_left) }
    end

    # @rbs (IR::Grammar grammar, IR::Production production, map_left: bool) -> production_signature
    def production_signature(grammar, production, map_left:)
      lhs = symbol_name(grammar, production.lhs)
      rhs = production.rhs.map { |id| symbol_name(grammar, id) }
      precedence = production.precedence_override
      precedence_name = symbol_name(grammar, precedence) if precedence
      [
        mapped_name(grammar, lhs, map_left: map_left),
        rhs.map { |name| mapped_name(grammar, name, map_left: map_left) },
        precedence_name && mapped_name(grammar, precedence_name, map_left: map_left)
      ]
    end

    # @rbs (IR::Grammar grammar, Integer id) -> String
    def symbol_name(grammar, id)
      symbol = grammar.symbol_by_id(id)
      symbol ? symbol.name : id.to_s
    end

    # @rbs (IR::Grammar grammar, String name, map_left: bool) -> String
    def mapped_name(grammar, name, map_left:)
      symbol = grammar.symbol(name)
      return name unless map_left && symbol&.nonterminal?

      @rule_map.fetch(name, name)
    end

    # @rbs () -> void
    def validate_rule_map!
      left_names = @left.grammar.nonterminals.map(&:name)
      right_names = @right.grammar.nonterminals.map(&:name)
      unknown_left = @rule_map.keys - left_names
      unknown_right = @rule_map.values - right_names
      raise ArgumentError, "unknown left rules: #{unknown_left.join(', ')}" unless unknown_left.empty?
      raise ArgumentError, "unknown right rules: #{unknown_right.join(', ')}" unless unknown_right.empty?
      return if @rule_map.values.uniq.length == @rule_map.length

      raise ArgumentError, "rule map must be one-to-one"
    end

    # @rbs () -> void
    def verify_inputs!
      { left: @left, right: @right }.each do |side, automaton|
        result = Verify::Verifier.new(automaton).verify
        next if result.valid?

        raise Ibex::Error,
              "(equiv):1:1: #{side} automaton failed independent verification: " \
              "#{result.violations.first&.message}"
      end
    end

    # @rbs () -> Array[String]
    def terminal_alphabet
      [@left, @right].flat_map do |automaton|
        automaton.grammar.terminals.reject(&:reserved).map(&:name)
      end.uniq.sort
    end

    # @rbs (Machine::Configuration left, Machine::Configuration right) -> Array[Object?]
    def product_key(left, right)
      key = [left.stack, left.status, left.actions, right.stack, right.status, right.actions]
      key.push(left.reductions, right.reductions) if tree_requested?
      key
    end

    # @rbs (Machine::Configuration left, Machine::Configuration right) -> bool
    def both_rejected?(left, right)
      left.status == :error && right.status == :error
    end

    # @rbs (structural: bool, samples: Integer, configurations: Integer) -> untyped
    def successful_report(structural:, samples:, configurations:)
      methods = if structural
                  ["structural_comparison"]
                else
                  %w[structural_comparison bidirectional_sampling bounded_product_bfs]
                end
      IR.deep_freeze(
        ibex_report: "equiv", schema_version: 1, result: "no_difference_within_bounds",
        structural_identity: structural,
        methods: methods,
        rule_map: @rule_map,
        tree: {
          requested: tree_requested?,
          result: tree_requested? ? "no_difference_within_bounds" : "not_checked"
        },
        checked: { samples: samples, product_configurations: configurations },
        bounds: bounds, statement: CAVEAT
      )
    end

    # @rbs () -> bool
    def tree_requested? = !@rule_map.empty?

    # @rbs () -> Hash[Symbol, Integer]
    def bounds
      {
        sample_count: @sample_count, seed: @seed, max_tokens: @max_tokens,
        max_configurations: @max_configurations, max_actions: @max_actions, max_stack: @max_stack
      }
    end

    # @rbs (Ibex::Error error) -> bool
    def sample_budget_error?(error)
      error.message.match?(/(?:limit|maximum|budget).*(?:exceed|exhaust)|needs \d+ tokens/i)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
