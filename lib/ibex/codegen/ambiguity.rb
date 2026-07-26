# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # @rbs!
    #   type ambiguity_search = {
    #     max_tokens: Integer,
    #     max_configurations: Integer
    #   }
    #   type ambiguity_summary = {
    #     conflicts: Integer,
    #     ambiguous: Integer,
    #     not_found: Integer,
    #     configuration_budget_exhausted: Integer
    #   }
    #   type ambiguity_check = {
    #     state: Integer,
    #     type: String,
    #     token: String,
    #     result: String,
    #     sentence: Array[String],
    #     lookahead_index: Integer?,
    #     interpretations: Array[IR::interpretation],
    #     explored_configurations: Integer,
    #     configuration_budget_exhausted: bool
    #   }
    #   type ambiguity_document = {
    #     ibex_check: String,
    #     schema_version: Integer,
    #     algorithm: String,
    #     search: ambiguity_search,
    #     status: String,
    #     summary: ambiguity_summary,
    #     conflicts: Array[ambiguity_check]
    #   }

    # Renders a bounded ambiguity search over every parser conflict.
    class Ambiguity
      SCHEMA_VERSION = 1 #: Integer

      # @rbs @automaton: IR::Automaton
      # @rbs @grammar: IR::Grammar
      # @rbs @max_tokens: Integer
      # @rbs @max_configurations: Integer
      # @rbs @checks: Array[ambiguity_check]

      # @rbs (IR::Automaton automaton, ?max_tokens: Integer, ?max_configurations: Integer) -> void
      def initialize(
        automaton,
        max_tokens: LALR::Counterexample::DEFAULT_MAX_TOKENS,
        max_configurations: LALR::Counterexample::DEFAULT_MAX_CONFIGURATIONS
      )
        LALR::ConflictSearchLimits.validate!(
          max_tokens: max_tokens, max_configurations: max_configurations
        )
        @automaton = automaton
        @grammar = automaton.grammar
        @max_tokens = max_tokens
        @max_configurations = max_configurations
        @checks = check_conflicts
      end

      # @rbs () -> Integer
      def exit_status
        return 1 if status == "ambiguous"
        return 2 if status == "inconclusive"

        0
      end

      # @rbs () -> ambiguity_document
      def to_h
        {
          ibex_check: "ambiguity",
          schema_version: SCHEMA_VERSION,
          algorithm: @automaton.algorithm,
          search: { max_tokens: @max_tokens, max_configurations: @max_configurations },
          status: status,
          summary: summary,
          conflicts: @checks
        }
      end

      # @rbs () -> String
      def render_text
        counts = summary
        lines = [
          "Ibex ambiguity check v#{SCHEMA_VERSION}",
          "Algorithm: #{@automaton.algorithm}",
          "Search budget: #{@max_tokens} tokens, #{@max_configurations} configurations per conflict",
          "Result: #{status}",
          "Conflicts: #{counts.fetch(:conflicts)}, ambiguous: #{counts.fetch(:ambiguous)}, " \
          "exhausted: #{counts.fetch(:configuration_budget_exhausted)}"
        ]
        @checks.each_with_index { |check, index| append_check(lines, check, index + 1) }
        "#{lines.join("\n")}\n"
      end

      private

      # @rbs () -> String
      def status
        return "ambiguous" if @checks.any? { |check| check.fetch(:result) == "ambiguous" }
        return "inconclusive" if @checks.any? { |check| check.fetch(:configuration_budget_exhausted) }

        "no_ambiguity_found_within_bounds"
      end

      # @rbs () -> ambiguity_summary
      def summary
        {
          conflicts: @checks.length,
          ambiguous: @checks.count { |check| check.fetch(:result) == "ambiguous" },
          not_found: @checks.count { |check| check.fetch(:result) == "not_found" },
          configuration_budget_exhausted: @checks.count do |check|
            check.fetch(:configuration_budget_exhausted)
          end
        }
      end

      # @rbs () -> Array[ambiguity_check]
      def check_conflicts
        @automaton.states.flat_map do |state|
          state.conflicts.map { |conflict| check_conflict(state, conflict) }
        end
      end

      # @rbs (IR::AutomatonState state, IR::conflict conflict) -> ambiguity_check
      def check_conflict(state, conflict)
        search = LALR::ConflictSearch.new(
          @automaton, state, conflict,
          max_tokens: @max_tokens, max_configurations: @max_configurations
        )
        result = search.call
        {
          state: state.id,
          type: conflict.fetch(:type).to_s,
          token: conflict.fetch(:symbol),
          result: result ? "ambiguous" : "not_found",
          sentence: result ? symbol_names(result.fetch(:sentence_ids)) : [],
          lookahead_index: result&.fetch(:lookahead_index),
          interpretations: result ? result.fetch(:interpretations) : [],
          explored_configurations: search.explored,
          configuration_budget_exhausted: search.exhausted?
        }
      end

      # @rbs (Array[Integer] ids) -> Array[String]
      def symbol_names(ids)
        ids.map do |id|
          symbol = @grammar.symbol_by_id(id) || raise(Ibex::Error, "missing grammar symbol id #{id}")
          symbol.display_name || symbol.name
        end
      end

      # @rbs (Array[String] lines, ambiguity_check check, Integer number) -> void
      def append_check(lines, check, number)
        lines << ""
        lines << "#{number}. State #{check.fetch(:state)}, #{check.fetch(:type)}, token #{check.fetch(:token)}"
        lines << "   Result: #{check.fetch(:result)}"
        sentence = check.fetch(:sentence)
        lines << "   Sentence: #{sentence.join(' ')}" unless sentence.empty?
        lines << "   Explored configurations: #{check.fetch(:explored_configurations)}"
        return unless check.fetch(:configuration_budget_exhausted)

        lines << "   Configuration budget exhausted before a counterexample was found."
      end
    end
  end
end
