# frozen_string_literal: true
# rbs_inline: enabled

# steep:ignore:start

# The iterative SCC implementation keeps all graph bookkeeping in one pass.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength

module Ibex
  module Analysis
    # Computes the transitive bit-set closure used by the LR lookahead
    # algorithms.  The implementation is iterative so a large grammar cannot
    # exhaust Ruby's call stack merely because its dependency graph is deep.
    module Digraph
      module_function

      # @rbs (Array[Integer] initial, Array[Array[Integer]] edges) -> Array[Integer]
      def closure(initial, edges)
        raise ArgumentError, "digraph edge count does not match values" unless initial.length == edges.length

        values = initial.dup
        components = strongly_connected_components(edges)
        component_edges = Array.new(components.length) { [] }
        component_for = Array.new(edges.length)
        components.each_with_index do |members, component_id|
          members.each { |vertex| component_for[vertex] = component_id }
        end
        edges.each_with_index do |successors, vertex|
          source = component_for.fetch(vertex)
          successors.each do |successor|
            target = component_for.fetch(successor)
            component_edges[source] << target if source != target
          end
        end
        component_edges.each(&:uniq!)

        order = topological_order(component_edges)
        order.reverse_each do |component_id|
          members = components.fetch(component_id)
          merged = members.reduce(0) { |bits, vertex| bits | values.fetch(vertex) }
          component_edges.fetch(component_id).each do |successor|
            merged |= values.fetch(components.fetch(successor).first)
          end
          members.each { |vertex| values[vertex] = merged }
        end
        values
      end

      # @rbs (Array[Array[Integer]] edges) -> Array[Array[Integer]]
      def strongly_connected_components(edges)
        index = 0
        indexes = Array.new(edges.length)
        lowlinks = Array.new(edges.length)
        on_stack = Array.new(edges.length, false)
        stack = []
        components = []
        visit = lambda do |root|
          frames = [[root, 0, false]]
          until frames.empty?
            vertex, offset, entered = frames[-1]
            unless entered
              indexes[vertex] = index
              lowlinks[vertex] = index
              index += 1
              stack << vertex
              on_stack[vertex] = true
              frames[-1][2] = true
            end

            successors = edges.fetch(vertex)
            if offset < successors.length
              successor = successors.fetch(offset)
              frames[-1][1] += 1
              if indexes[successor].nil?
                frames << [successor, 0, false]
              elsif on_stack[successor]
                lowlinks[vertex] = [lowlinks[vertex], indexes[successor]].min
              end
              next
            end

            if lowlinks[vertex] == indexes[vertex]
              component = []
              loop do
                member = stack.pop
                on_stack[member] = false
                component << member
                break if member == vertex
              end
              components << component.sort
            end
            frames.pop
            next if frames.empty?

            parent = frames[-1][0]
            lowlinks[parent] = [lowlinks[parent], lowlinks[vertex]].min
          end
        end
        edges.each_index { |vertex| visit.call(vertex) if indexes[vertex].nil? }
        components
      end
      private_class_method :strongly_connected_components

      # @rbs (Array[Array[Integer]]) -> Array[Integer]
      def topological_order(edges)
        indegree = Array.new(edges.length, 0)
        edges.each { |successors| successors.each { |successor| indegree[successor] += 1 } }
        queue = indegree.each_index.select { |vertex| indegree[vertex].zero? }
        order = []
        until queue.empty?
          vertex = queue.shift
          order << vertex
          edges.fetch(vertex).each do |successor|
            indegree[successor] -= 1
            queue << successor if indegree[successor].zero?
          end
        end
        raise Ibex::Error, "digraph contains a cyclic component graph" unless order.length == edges.length

        order
      end
      private_class_method :topological_order
    end
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
# steep:ignore:end
