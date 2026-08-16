# frozen_string_literal: true
# rbs_inline: enabled

require_relative "graph"

module Ibex
  module Impact
    # One shortest witness for a symbol reached by dependency propagation.
    class Node
      attr_reader :symbol #: Integer
      attr_reader :distance #: Integer
      attr_reader :witness #: Array[Edge]
      attr_reader :kind #: Symbol
      attr_reader :component #: Array[Integer]

      # @rbs (symbol: Integer, distance: Integer, witness: Array[Edge], kind: Symbol, component: Array[Integer]) -> void
      def initialize(symbol:, distance:, witness:, kind:, component:)
        @symbol = symbol
        @distance = distance
        @witness = witness.freeze
        @kind = kind
        @component = component.freeze
        freeze
      end
    end

    # Performs deterministic forward propagation over a dependency graph.
    class Propagation
      # @rbs @graph: Graph
      # @rbs (Graph graph) -> void
      def initialize(graph)
        @graph = graph
      end

      # @rbs (Array[Integer] seeds, Symbol kind, ?max_depth: Integer?) -> Hash[Integer, Node]
      def propagate(seeds, kind = :all, max_depth: nil)
        validate_depth(max_depth)
        selected = normalize_seeds(seeds)
        adjacency = @graph.adjacency(kind)
        components = Analysis::Digraph.send(:strongly_connected_components, adjacency)
        component_for = component_index(components, adjacency.length)
        component_edges = component_adjacency(adjacency, component_for, components.length)
        component_nodes = traverse_components(selected, component_for, component_edges, max_depth)
        witnesses = symbol_witnesses(selected, adjacency, kind)
        build_nodes(component_nodes, components, kind, witnesses)
      end

      alias call propagate

      private

      # @rbs (Integer?) -> void
      def validate_depth(max_depth)
        return if max_depth.nil? || (max_depth.is_a?(Integer) && max_depth >= 0)

        raise ArgumentError, "impact depth must be a non-negative integer"
      end

      # @rbs (Array[Integer]) -> Array[Integer]
      def normalize_seeds(seeds)
        seeds.uniq.sort.each do |id|
          unless @graph.grammar.symbol_by_id(id)
            raise ArgumentError,
                  "impact seed #{id.inspect} is not a grammar symbol"
          end
        end
      end

      # @rbs (Array[Array[Integer]], Integer) -> Array[Integer]
      def component_index(components, size)
        result = Array.new(size, 0) #: Array[Integer]
        components.each_with_index { |members, id| members.each { |member| result[member] = id } }
        result
      end

      # @rbs (Array[Array[Integer]], Array[Integer], Integer) -> Array[Array[Integer]]
      def component_adjacency(adjacency, component_for, component_count)
        result = Array.new(component_count) { [] } #: Array[Array[Integer]]
        adjacency.each_with_index do |successors, source|
          source_component = component_for.fetch(source)
          successors.each do |target|
            target_component = component_for.fetch(target)
            next if source_component == target_component

            result[source_component] << target_component
          end
        end
        result.each do |successors|
          successors.uniq!
          successors.sort!
        end
        result
      end

      # @rbs (Array[Integer], Array[Integer], Array[Array[Integer]], Integer?) -> Hash[Integer, Integer]
      def traverse_components(seeds, component_for, component_edges, max_depth)
        queue = seeds.uniq.sort.map do |seed|
          [component_for.fetch(seed), 0]
        end #: Array[[Integer, Integer]]
        result = {} #: Hash[Integer, Integer]
        until queue.empty?
          component, distance = queue.shift
          next if result.key?(component)
          next if max_depth && distance > max_depth

          result[component] = distance
          component_edges.fetch(component).each do |target|
            queue << [target, distance + 1]
          end
        end
        result
      end

      # @rbs (Array[Integer], Array[Array[Integer]], Symbol) -> Hash[Integer, Array[Edge]]
      def symbol_witnesses(seeds, adjacency, kind)
        edges = @graph.edges(kind).group_by { |edge| [edge.source, edge.target] }
        queue = seeds.uniq.sort.map { |seed| [seed, []] } #: Array[[Integer, Array[Edge]]]
        result = {} #: Hash[Integer, Array[Edge]]
        until queue.empty?
          symbol, witness = queue.shift
          next if result.key?(symbol)

          result[symbol] = witness
          adjacency.fetch(symbol).each do |target|
            edge = edges.fetch([symbol, target]).fetch(0)
            queue << [target, witness + [edge]]
          end
        end
        result
      end

      # @rbs (Hash[Integer, Integer], Array[Array[Integer]], Symbol, Hash[Integer, Array[Edge]]) -> Hash[Integer, Node]
      def build_nodes(component_nodes, components, kind, witnesses)
        result = {} #: Hash[Integer, Node]
        component_nodes.each do |component, distance|
          members = components.fetch(component).sort
          members.each do |symbol|
            result[symbol] = Node.new(
              symbol: symbol, distance: distance, witness: witnesses.fetch(symbol), kind: kind, component: members
            )
          end
        end
        result.sort.to_h
      end
    end
  end
end
