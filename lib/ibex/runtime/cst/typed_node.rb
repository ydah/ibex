# frozen_string_literal: true
# rbs_inline: enabled

require_relative "syntax_node" unless defined?(Ibex::Runtime::CST::SyntaxNode)

module Ibex
  module Runtime
    module CST
      # Grammar-generated typed view over one Red syntax node.
      class TypedNode
        # @rbs! type element = SyntaxNode | SyntaxToken

        attr_reader :node #: SyntaxNode

        # @rbs (SyntaxNode node) -> void
        def initialize(node)
          @node = node
          freeze
        end

        # @rbs () -> Integer
        def kind = @node.kind

        # @rbs () -> String
        def kind_name = @node.kind_name

        # @rbs (Integer index) -> element
        def child_at_slot(index) = @node.child_at(index)

        # @rbs (Integer index) -> SyntaxNode
        def node_at_slot(index)
          child = child_at_slot(index)
          return child if child.is_a?(SyntaxNode)

          raise TypeError, "CST slot #{index} is not a syntax node"
        end

        # @rbs (Integer index) -> SyntaxToken
        def token_at_slot(index)
          child = child_at_slot(index)
          return child if child.is_a?(SyntaxToken)

          raise TypeError, "CST slot #{index} is not a syntax token"
        end

        # @rbs () -> Array[element]
        def deconstruct = @node.deconstruct

        # @rbs (Array[Symbol]?) -> Hash[Symbol, untyped]
        def deconstruct_keys(keys) = @node.deconstruct_keys(keys)

        # @rbs () -> String
        def to_source = @node.to_source

        protected

        # Flatten a lowered repetition helper and enumerate elements or separators.
        # @rbs (Integer index, separated: bool, ?separators: bool) -> Enumerator[element, void]
        def list_items(index, separated:, separators: false)
          root = node_at_slot(index)
          flattened = [] #: Array[element]
          flatten_list(root, root.kind, flattened)
          return flattened.each unless separated

          selected = [] #: Array[element]
          flattened.each_with_index do |item, item_index|
            selected << item if separators == item_index.odd?
          end
          selected.each
        end

        private

        # @rbs (SyntaxNode current, Integer helper_kind, Array[element] result) -> void
        def flatten_list(current, helper_kind, result)
          current.children.each do |child|
            if child.is_a?(SyntaxNode) && child.kind == helper_kind
              flatten_list(child, helper_kind, result)
            else
              result << child
            end
          end
        end
      end
    end
  end
end
