# frozen_string_literal: true
# rbs_inline: enabled

require "set"

module Ibex
  # Deterministic structural metrics over normalized Grammar and Automaton IR.
  class Metrics
    # @rbs (IR::Automaton automaton) -> void
    def initialize(automaton)
      @automaton = automaton
      @grammar = automaton.grammar
    end

    # @rbs () -> Hash[Symbol, untyped]
    def to_h
      {
        ibex_report: "metrics", schema_version: 1,
        algorithm: @automaton.algorithm,
        grammar_digest: @automaton.grammar_digest,
        symbols: symbol_metrics,
        grammar: grammar_metrics,
        automaton: automaton_metrics
      }
    end

    private

    # @rbs () -> Hash[Symbol, Integer]
    def symbol_metrics
      { terminals: @grammar.terminals.length, nonterminals: @grammar.nonterminals.length }
    end

    # @rbs () -> Hash[Symbol, untyped]
    def grammar_metrics
      rule_counts = @grammar.productions.group_by(&:lhs).transform_values(&:length)
      {
        rules: rule_counts.length,
        alternatives: @grammar.productions.length,
        average_alternatives_per_rule: average(rule_counts.values),
        maximum_branching: rule_counts.values.max || 0,
        epsilon_productions: @grammar.productions.count { |production| production.rhs.empty? },
        recursive_nonterminals: recursive_nonterminal_ids.map { |id| symbol_name(id) }.sort,
        recursion_component_depth: recursion_component_depth,
        warnings: @grammar.warnings.length
      }
    end

    # @rbs () -> Hash[Symbol, untyped]
    def automaton_metrics
      {
        states: @automaton.states.length,
        transitions: @automaton.states.sum { |state| state.transitions.length },
        action_cells: @automaton.states.sum { |state| state.actions.length },
        goto_cells: @automaton.states.sum { |state| state.gotos.length },
        default_reductions: @automaton.states.count(&:default_action),
        conflicts: {
          shift_reduce: @automaton.conflict_summary.fetch(:sr),
          precedence_resolved_shift_reduce: @automaton.conflict_summary.fetch(:resolved_sr),
          reduce_reduce: @automaton.conflict_summary.fetch(:rr)
        }
      }
    end

    # @rbs (Array[Integer] values) -> Float
    def average(values)
      return 0.0 if values.empty?

      values.sum.fdiv(values.length).round(6)
    end

    # @rbs () -> Hash[Integer, Array[Integer]]
    def dependency_graph
      @dependency_graph ||= begin
        graph = {} #: Hash[Integer, Array[Integer]]
        @grammar.nonterminals.each { |symbol| graph[symbol.id] = [] }
        @grammar.productions.each do |production|
          production.rhs.each do |id|
            symbol = @grammar.symbol_by_id(id)
            graph.fetch(production.lhs) << id if symbol&.nonterminal?
          end
        end
        graph.transform_values { |targets| targets.uniq.sort }
      end
    end

    # @rbs () -> Hash[Integer, Set[Integer]]
    def reachability
      @reachability ||= dependency_graph.to_h do |source, _targets|
        found = Set[source]
        queue = [source]
        cursor = 0
        while cursor < queue.length
          dependency_graph.fetch(queue.fetch(cursor)).each do |target|
            next if found.include?(target)

            found << target
            queue << target
          end
          cursor += 1
        end
        [source, found]
      end
    end

    # @rbs () -> Array[Array[Integer]]
    def recursion_components
      remaining = dependency_graph.keys.sort
      components = [] #: Array[Array[Integer]]
      until remaining.empty?
        source = remaining.fetch(0)
        component = remaining.select do |candidate|
          reachability.fetch(source).include?(candidate) && reachability.fetch(candidate).include?(source)
        end
        components << component
        remaining -= component
      end
      components
    end

    # @rbs () -> Array[Integer]
    def recursive_nonterminal_ids
      recursion_components.flat_map do |component|
        next component if component.length > 1

        id = component.fetch(0)
        dependency_graph.fetch(id).include?(id) ? component : []
      end
    end

    # Longest path after collapsing mutually recursive nonterminals.
    # @rbs () -> Integer
    def recursion_component_depth
      components = recursion_components
      component_for = {} #: Hash[Integer, Integer]
      components.each_with_index { |ids, index| ids.each { |id| component_for[id] = index } }
      edges = Array.new(components.length) { Set.new } #: Array[Set[Integer]]
      dependency_graph.each do |source, targets|
        targets.each do |target|
          from = component_for.fetch(source)
          to = component_for.fetch(target)
          edges.fetch(from) << to unless from == to
        end
      end
      longest_dag_path(edges)
    end

    # @rbs (Array[Set[Integer]] edges) -> Integer
    def longest_dag_path(edges)
      indegree = Array.new(edges.length, 0)
      edges.each { |targets| targets.each { |target| indegree[target] += 1 } }
      depths = Array.new(edges.length, 1)
      queue = indegree.each_index.select { |index| indegree[index].zero? }
      cursor = 0
      while cursor < queue.length
        source = queue.fetch(cursor)
        edges.fetch(source).each do |target|
          depths[target] = [depths[target], depths[source] + 1].max
          indegree[target] -= 1
          queue << target if indegree[target].zero?
        end
        cursor += 1
      end
      depths.max || 0
    end

    # @rbs (Integer id) -> String
    def symbol_name(id)
      @grammar.symbol_by_id(id)&.name || id.to_s
    end
  end
end
