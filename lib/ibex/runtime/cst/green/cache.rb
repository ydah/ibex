# frozen_string_literal: true
# rbs_inline: enabled

require_relative "node" unless defined?(Ibex::Runtime::CST::GreenNode)

module Ibex
  module Runtime
    module CST
      # Session-owned hash-consing cache for immutable Green elements.
      class NodeCache
        DEFAULT_NODE_ARITY_LIMIT = 3 #: Integer

        # @rbs @enabled: bool
        # @rbs @node_arity_limit: Integer
        # @rbs @tokens: Hash[GreenToken, GreenToken]
        # @rbs @nodes: Hash[GreenNode, GreenNode]

        # @rbs (?enabled: bool, ?node_arity_limit: Integer) -> void
        def initialize(enabled: true, node_arity_limit: DEFAULT_NODE_ARITY_LIMIT)
          raise ArgumentError, "node_arity_limit must be non-negative" if node_arity_limit.negative?

          @enabled = enabled
          @node_arity_limit = node_arity_limit
          @tokens = {}
          @nodes = {}
        end

        # @rbs (GreenToken token) -> GreenToken
        def intern_token(token)
          return token unless @enabled
          return token unless token.flags.nobits?(Flags::HAS_ANNOTATION)

          @tokens[token] ||= token
        end

        # @rbs (GreenNode node) -> GreenNode
        def intern_node(node)
          return node unless @enabled
          return node if node.children.length > @node_arity_limit
          return node unless node.flags.nobits?(Flags::HAS_ANNOTATION)

          @nodes[node] ||= node
        end

        # @rbs () -> void
        def clear
          @tokens.clear
          @nodes.clear
        end
      end
    end
  end
end
