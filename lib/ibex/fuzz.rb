# frozen_string_literal: true
# rbs_inline: enabled

require_relative "samples"
require_relative "table_simulation"
require_relative "delta_reducer"

module Ibex
  # @rbs!
  #   type fuzz_outcome = Symbol | [Symbol, String, String]
  #   type fuzz_mismatch = {
  #     tokens: Array[String],
  #     kind: Symbol,
  #     sentence: Integer,
  #     outcomes: Hash[Symbol, fuzz_outcome],
  #     bounds: Hash[Symbol, Integer]
  #   }
  #   type fuzz_budget = {
  #     message: String,
  #     bounds: Hash[Symbol, Integer],
  #     ?tokens: Array[String],
  #     ?phase: String
  #   }

  # Bounded grammar-derived differential fuzzing without semantic execution.
  class Fuzz
    ALGORITHMS = %i[slr lalr ielr lr1].freeze #: Array[Symbol]
    DEFAULT_MAX_ACTIONS = 100_000 #: Integer
    DEFAULT_MAX_STACK = 10_000 #: Integer

    class Mismatch < Ibex::Error
      attr_reader :details #: fuzz_mismatch

      # @rbs (fuzz_mismatch details) -> void
      def initialize(details)
        @details = IR.deep_freeze(details)
        super("(fuzz):1:1: differential mismatch for #{details[:tokens].inspect}")
      end
    end

    class BudgetExceeded < Ibex::Error
      attr_reader :details #: fuzz_budget

      # @rbs (fuzz_budget details) -> void
      def initialize(details)
        @details = IR.deep_freeze(details)
        super("(fuzz):1:1: configured budget was exhausted: #{details[:message]}")
      end
    end

    # @rbs (IR::Grammar grammar, ?seed: Integer, ?count: Integer, ?max_tokens: Integer,
    #   ?max_depth: Integer, ?max_expansions: Integer, ?max_actions: Integer, ?max_stack: Integer,
    #   ?coverage_guided: bool, ?path_length: Integer, ?algorithms: Array[Symbol],
    #   ?automata: Hash[Symbol, IR::Automaton]?, ?against: (^(Array[String]) -> Symbol)?,
    #   ?against_description: Hash[Symbol, Object?]?) -> void
    # rubocop:disable Metrics/ParameterLists
    def initialize(grammar, seed: 0, count: 100, max_tokens: 32, max_depth: 16,
                   max_expansions: Samples::DEFAULT_MAX_EXPANSIONS, max_actions: DEFAULT_MAX_ACTIONS,
                   max_stack: DEFAULT_MAX_STACK, coverage_guided: false, path_length: 2,
                   algorithms: ALGORITHMS, automata: nil, against: nil, against_description: nil)
      raise ArgumentError, "count must be positive" unless count.positive?
      raise ArgumentError, "algorithms must not be empty" if algorithms.empty?

      @grammar = grammar
      @seed = seed
      @count = count
      @random = Random.new(seed ^ 0x1BE)
      @max_tokens = max_tokens
      @max_depth = max_depth
      @max_expansions = max_expansions
      @max_actions = max_actions
      @max_stack = max_stack
      @coverage_guided = coverage_guided
      @path_length = path_length
      @algorithms = algorithms.map(&:to_sym).freeze
      @automata = automata || build_automata
      @against = against
      @against_description = against_description
    end
    # rubocop:enable Metrics/ParameterLists

    # @rbs () -> Hash[Symbol, Object?]
    def run
      sentences = generate_sentences
      mutation_count = 0
      sentences.each_with_index do |tokens, index|
        compare!(tokens, kind: :generated, sentence: index)
        mutations(tokens).each do |mutation|
          compare!(mutation, kind: :mutation, sentence: index)
          mutation_count += 1
        end
      end
      successful_report(sentences.length, mutation_count)
    rescue Ibex::Error => e
      raise if e.is_a?(Mismatch) || e.is_a?(BudgetExceeded) || !budget_error?(e)

      raise BudgetExceeded.new(
        message: e.message,
        bounds: { max_expansions: @max_expansions, max_actions: @max_actions, max_stack: @max_stack }
      )
    end

    # Minimize one observed mismatch without changing its kind or outcomes.
    # @rbs (Mismatch mismatch, ?max_trials: Integer) -> DeltaReducer::Result
    def minimize(mismatch, max_trials: 1_000)
      details = mismatch.details
      original = details[:tokens]
      kind = details[:kind].to_sym
      sentence = details[:sentence]
      outcomes = details[:outcomes]
      DeltaReducer.new(max_trials: max_trials).minimize(original) do |candidate|
        mismatch_reproduced?(candidate, kind: kind, sentence: sentence, outcomes: outcomes)
      end
    end

    private

    # @rbs () -> Array[Array[String]]
    def generate_sentences
      Samples.new(
        @grammar, seed: @seed, max_tokens: @max_tokens, max_depth: @max_depth,
                  max_expansions: @max_expansions, strategy: @coverage_guided ? :coverage : :random,
                  path_length: @path_length
      ).generate(count: @count)
    end

    # @rbs (Integer sentence_count, Integer mutation_count) -> Hash[Symbol, Object?]
    def successful_report(sentence_count, mutation_count)
      report = {
        ibex_report: "fuzz", schema_version: 1, seed: @seed,
        bounds: {
          sentences: @count, max_tokens: @max_tokens, max_depth: @max_depth,
          max_expansions: @max_expansions, max_actions: @max_actions, max_stack: @max_stack
        },
        strategy: @coverage_guided ? "coverage" : "random",
        path_length: @path_length,
        algorithms: @algorithms.map(&:to_s),
        generated_sentences: sentence_count,
        mutated_sentences: mutation_count,
        result: "no_difference_within_bounds"
      }
      report[:external] = @against_description if @against_description
      IR.deep_freeze(report)
    end

    # @rbs () -> Hash[Symbol, IR::Automaton]
    def build_automata
      @algorithms.to_h do |algorithm|
        [algorithm, LALR::Builder.new(@grammar, algorithm: algorithm).build]
      end
    end

    # @rbs (Array[String] tokens, kind: Symbol, sentence: Integer) -> void
    def compare!(tokens, kind:, sentence:)
      outcomes = @algorithms.to_h do |algorithm|
        automaton = @automata.fetch(algorithm)
        simulator = TableSimulation::Simulator.new(
          automaton, max_steps: @max_actions, max_stack: @max_stack
        )
        [algorithm, simulator.simulate(tokens).status]
      rescue Ibex::Error => e
        if budget_error?(e)
          raise BudgetExceeded.new(
            message: e.message, tokens: tokens,
            bounds: { max_actions: @max_actions, max_stack: @max_stack }
          )
        end
        [algorithm, [:failure, e.class.name, e.message]]
      end
      outcomes[:external] = @against.call(tokens) if @against
      values = outcomes.values.uniq
      return if values.length == 1 && (kind != :generated || values.first == :accepted)

      raise Mismatch.new(tokens: tokens, kind: kind, sentence: sentence, outcomes: outcomes,
                         bounds: { max_actions: @max_actions, max_stack: @max_stack })
    end

    # @rbs (Array[String] tokens) -> Array[Array[String]]
    def mutations(tokens)
      terminals = @grammar.terminals.reject(&:reserved).map(&:name)
      replacement = terminals.fetch(@random.rand(terminals.length))
      index = tokens.empty? ? 0 : @random.rand(tokens.length)
      inserted = tokens.dup.insert(index, replacement)
      return [inserted] if tokens.empty?

      deleted = tokens.dup.tap { |items| items.delete_at(index) }
      replaced = tokens.dup.tap { |items| items[index] = replacement }
      [inserted, deleted, replaced].uniq
    end

    # @rbs (Array[String] tokens, kind: Symbol, sentence: Integer,
    #   outcomes: Hash[Symbol, fuzz_outcome]) -> bool
    def mismatch_reproduced?(tokens, kind:, sentence:, outcomes:)
      compare!(tokens, kind: kind, sentence: sentence)
      false
    rescue Mismatch => e
      e.details[:kind].to_sym == kind &&
        e.details[:outcomes] == outcomes
    end

    # @rbs (Ibex::Error error) -> bool
    def budget_error?(error)
      error.message.match?(
        /simulation exceeded|(?:limit|maximum|budget).*(?:exceed|exhaust)|exceed.*(?:limit|maximum|budget)/i
      )
    end
  end
end
