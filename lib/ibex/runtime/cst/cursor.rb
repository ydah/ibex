# frozen_string_literal: true
# rbs_inline: enabled

require_relative "syntax_node" unless defined?(Ibex::Runtime::CST::SyntaxNode)

module Ibex
  module Runtime
    module CST
      # Allocation-light cursor over Green elements and absolute offsets.
      # rubocop:disable Naming/PredicateMethod -- cursor movement names follow the public tree-cursor convention.
      class Cursor
        # @rbs! type green = GreenNode | GreenToken
        # @rbs! type frame = [GreenNode, Integer, Integer]

        attr_reader :green #: green
        attr_reader :offset #: Integer

        # @rbs (SyntaxNode node) -> void
        def initialize(node)
          @green = node.green
          @offset = node.offset
          @frames = [] #: Array[frame]
        end

        # @rbs () -> bool
        def goto_first_child
          green = @green
          return false unless green.is_a?(GreenNode)
          return false if green.children.empty?

          parent = green
          @frames << [parent, 0, @offset]
          @green = parent.children.fetch(0)
          true
        end

        # @rbs () -> bool
        def goto_next_sibling
          frame = @frames.last
          return false unless frame

          parent, index, parent_offset = frame
          next_index = index + 1
          return false if next_index >= parent.children.length

          frame[1] = next_index
          @offset = parent_offset + parent.children.first(next_index).sum(&:full_width)
          @green = parent.children.fetch(next_index)
          true
        end

        # @rbs () -> bool
        def goto_parent
          frame = @frames.pop
          return false unless frame

          @green = frame.fetch(0)
          @offset = frame.fetch(2)
          true
        end

        # @rbs () -> Integer
        def kind = @green.kind
      end
      # rubocop:enable Naming/PredicateMethod
    end
  end
end
