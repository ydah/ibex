# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Deterministic grammar and automaton change classification.
  class Diff
    # @rbs (IR::Automaton before, IR::Automaton after) -> void
    def initialize(before, after)
      @before = before
      @after = after
    end

    # @rbs () -> Hash[Symbol, Object?]
    def to_h
      {
        ibex_report: "diff", schema_version: 1,
        symbols: classify(symbol_records(@before.grammar), symbol_records(@after.grammar)),
        rules: classify(rule_records(@before.grammar), rule_records(@after.grammar)),
        conflicts: classify(conflict_records(@before), conflict_records(@after)),
        warnings: classify(warning_records(@before.grammar), warning_records(@after.grammar)),
        metrics: numeric_metrics
      }
    end

    private

    # @rbs (Hash[String, Object?] before, Hash[String, Object?] after) -> Hash[Symbol, Object?]
    def classify(before, after)
      common = before.keys & after.keys
      {
        added: (after.keys - before.keys).sort.map { |key| { id: key, value: after.fetch(key) } },
        removed: (before.keys - after.keys).sort.map { |key| { id: key, value: before.fetch(key) } },
        changed: common.sort.filter_map do |key|
          next if before.fetch(key) == after.fetch(key)

          { id: key, before: before.fetch(key), after: after.fetch(key) }
        end
      }
    end

    # @rbs (IR::Grammar grammar) -> Hash[String, Object?]
    def symbol_records(grammar)
      grammar.symbols.to_h do |symbol|
        [
          symbol.name,
          {
            kind: symbol.kind, reserved: symbol.reserved, display_name: symbol.display_name,
            semantic_type: symbol.semantic_type, precedence: symbol.precedence
          }
        ]
      end
    end

    # @rbs (IR::Grammar grammar) -> Hash[String, Object?]
    def rule_records(grammar)
      grammar.productions.group_by(&:lhs).to_h do |lhs, productions|
        name = grammar.symbol_by_id(lhs)&.name || lhs.to_s
        alternatives = productions.map { |production| production_record(grammar, production) }
        [name, alternatives]
      end
    end

    # @rbs (IR::Grammar grammar, IR::Production production) -> Hash[Symbol, Object?]
    def production_record(grammar, production)
      precedence = production.precedence_override
      {
        rhs: production.rhs.map { |id| symbol_name(grammar, id) },
        precedence: precedence && symbol_name(grammar, precedence),
        node: production.node && {
          name: production.node.fetch(:name), fields: production.node.fetch(:fields)
        }
      }
    end

    # @rbs (IR::Automaton automaton) -> Hash[String, Object?]
    def conflict_records(automaton)
      grouped = Hash.new { |hash, key| hash[key] = [] } #: Hash[String, Array[Object?]]
      automaton.states.each do |state|
        state.conflicts.each do |conflict|
          identity = conflict_identity(automaton.grammar, conflict)
          grouped[identity] << conflict.fetch(:resolution)
        end
      end
      grouped.transform_values { |resolutions| resolutions.sort_by(&:inspect) }
    end

    # @rbs (IR::Grammar grammar, IR::conflict conflict) -> String
    def conflict_identity(grammar, conflict)
      if conflict.fetch(:type).to_sym == :shift_reduce
        shift_reduce = conflict #: IR::shift_reduce_conflict
        reduction = production_shape(grammar, shift_reduce.fetch(:reduce))
        "shift_reduce:#{shift_reduce.fetch(:symbol)}:#{reduction}"
      else
        reduce_reduce = conflict #: IR::reduce_reduce_conflict
        reductions = reduce_reduce.fetch(:reductions).map { |id| production_shape(grammar, id) }.sort
        "reduce_reduce:#{reduce_reduce.fetch(:symbol)}:#{reductions.join('|')}"
      end
    end

    # @rbs (IR::Grammar grammar, Integer id) -> String
    def production_shape(grammar, id)
      production = grammar.productions.fetch(id)
      lhs = symbol_name(grammar, production.lhs)
      rhs = production.rhs.map { |symbol| symbol_name(grammar, symbol) }
      "#{lhs}->#{rhs.join(' ')}"
    end

    # @rbs (IR::Grammar grammar, Integer id) -> String
    def symbol_name(grammar, id)
      grammar.symbol_by_id(id)&.name || id.to_s
    end

    # @rbs (IR::Grammar grammar) -> Hash[String, Object?]
    def warning_records(grammar)
      grouped = Hash.new { |hash, key| hash[key] = [] } #: Hash[String, Array[Object?]]
      grammar.warnings.each do |warning|
        value = warning.except(:loc)
        identity = [warning.fetch(:type), value.except(:message).inspect].join(":")
        grouped[identity] << value
      end
      grouped.transform_values { |values| values.sort_by(&:inspect) }
    end

    # @rbs () -> Hash[Symbol, Hash[Symbol, Integer]]
    def numeric_metrics
      {
        states: change(@before.states.length, @after.states.length),
        productions: change(@before.grammar.productions.length, @after.grammar.productions.length),
        warnings: change(@before.grammar.warnings.length, @after.grammar.warnings.length),
        shift_reduce: change(@before.conflict_summary.fetch(:sr), @after.conflict_summary.fetch(:sr)),
        reduce_reduce: change(@before.conflict_summary.fetch(:rr), @after.conflict_summary.fetch(:rr))
      }
    end

    # @rbs (Integer before, Integer after) -> Hash[Symbol, Integer]
    def change(before, after)
      { before: before, after: after, delta: after - before }
    end
  end
end
