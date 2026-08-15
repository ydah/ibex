# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../analysis"

module Ibex
  module Impact
    # A grammar dependency edge with enough origin information for a witness.
    class Edge
      attr_reader :source #: Integer
      attr_reader :target #: Integer
      attr_reader :kind #: Symbol
      attr_reader :production #: Integer?
      attr_reader :position #: Integer?

      # @rbs (source: Integer, target: Integer, kind: Symbol, production: Integer?, position: Integer?) -> void
      def initialize(source:, target:, kind:, production: nil, position: nil)
        @source = source
        @target = target
        @kind = kind.to_sym
        @production = production
        @position = position
        freeze
      end

      # @rbs () -> Array[Integer | Symbol | nil]
      def sort_key
        [@source, @target, @production || -1, @position || -1, @kind]
      end
    end

    # Combines reference, FIRST, and FOLLOW propagation dependencies.
    class Graph
      EDGE_KINDS = %i[reference first follow_lhs follow_first].freeze #: Array[Symbol]
      KIND_ALIASES = {
        all: EDGE_KINDS, reference: [:reference], first: [:first], follow: %i[follow_lhs follow_first],
        follow_lhs: [:follow_lhs], follow_first: [:follow_first]
      }.freeze #: Hash[Symbol, Array[Symbol]]

      attr_reader :grammar #: IR::Grammar
      attr_reader :sets #: Analysis::Sets

      # @rbs (IR::Grammar grammar, ?sets: Analysis::Sets) -> void
      def initialize(grammar, sets: nil)
        @grammar = grammar
        @sets = sets || Analysis::Sets.new(grammar)
        @edges = build_edges
        freeze_edges
      end

      # @rbs (?Symbol kind) -> untyped
      def edges(kind = :all)
        selected = KIND_ALIASES.fetch(kind.to_sym) { raise ArgumentError, "unknown impact edge kind #{kind}" }
        return selected.flat_map { |name| @edges.fetch(name) }.sort_by(&:sort_key) if selected.length > 1

        @edges.fetch(selected.fetch(0))
      end

      # @rbs (Symbol kind) -> Array[Array[Integer]]
      def adjacency(kind)
        result = Array.new(@grammar.symbols.length) { [] }
        edges(kind).each { |edge| result[edge.source] << edge.target }
        result.each(&:uniq!)
        result
      end

      private

      # @rbs () -> Hash[Symbol, Array[Edge]]
      def build_edges
        result = EDGE_KINDS.to_h { |kind| [kind, []] }
        @grammar.productions.each do |production|
          add_production_edges(result, production)
        end
        result.each_value { |edges| edges.sort_by!(&:sort_key) }
        result
      end

      # @rbs (Hash[Symbol, Array[Edge]], IR::Production) -> void
      def add_production_edges(result, production)
        production.rhs.each_with_index do |symbol_id, position|
          next unless @grammar.symbol_by_id(symbol_id)&.nonterminal?

          result[:reference] << edge(symbol_id, production.lhs, :reference, production, position)
          add_first_edge(result, production, symbol_id, position)
          add_follow_edges(result, production, symbol_id, position)
        end
      end

      # @rbs (Hash[Symbol, Array[Edge]], IR::Production, Integer, Integer) -> void
      def add_first_edge(result, production, symbol_id, position)
        prefix = production.rhs[0...position] || []
        return unless @sets.sequence_nullable?(prefix)
        return unless @sets.first_dependencies.fetch(symbol_id).include?(production.lhs)

        result[:first] << edge(symbol_id, production.lhs, :first, production, position)
      end

      # @rbs (Hash[Symbol, Array[Edge]], IR::Production, Integer, Integer) -> void
      def add_follow_edges(result, production, symbol_id, position)
        suffix = production.rhs[(position + 1)..] || []
        if @sets.sequence_nullable?(suffix) && @sets.follow_dependencies.fetch(production.lhs).include?(symbol_id)
          result[:follow_lhs] << edge(production.lhs, symbol_id, :follow_lhs, production, position)
        end
        add_follow_first_edges(result, production, symbol_id, position)
      end

      # @rbs (Hash[Symbol, Array[Edge]], IR::Production, Integer, Integer) -> void
      def add_follow_first_edges(result, production, symbol_id, position)
        suffix = production.rhs[(position + 1)..] || []
        suffix.each_with_index do |candidate, offset|
          candidate_prefix = suffix[0...offset] || []
          break unless @sets.sequence_nullable?(candidate_prefix)
          break unless @grammar.symbol_by_id(candidate)&.nonterminal?

          result[:follow_first] << edge(candidate, symbol_id, :follow_first, production, position + 1 + offset)
        end
      end

      # @rbs (Integer source, Integer target, Symbol kind, IR::Production production, Integer position) -> Edge
      def edge(source, target, kind, production, position)
        Edge.new(source: source, target: target, kind: kind, production: production.id, position: position)
      end

      # @rbs () -> void
      def freeze_edges
        @edges.each_value(&:freeze)
        @edges.freeze
      end
    end
  end
end
