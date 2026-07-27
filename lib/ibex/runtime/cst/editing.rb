# frozen_string_literal: true
# rbs_inline: enabled

require_relative "syntax_node" unless defined?(Ibex::Runtime::CST::SyntaxNode)

module Ibex
  module Runtime
    module CST
      # Shared path-copying operations for Red syntax elements.
      module Editing
        # @rbs! type element = SyntaxNode | SyntaxToken
        # @rbs! type green = GreenNode | GreenToken

        # @rbs (element target, green | element replacement) -> SyntaxNode
        def replace(target, replacement)
          green = green_element(replacement)
          current = target
          parent = target.parent
          while parent
            children = parent.green.children.dup
            children[current.index] = green
            green = GreenNode.new(
              kind: parent.green.kind, children: children,
              flags: parent.green.intrinsic_flags, annotations: parent.green.annotations
            )
            current = parent
            parent = parent.parent
          end
          raise TypeError, "the root replacement must be a GreenNode" unless green.is_a?(GreenNode)

          red_root(target.root, green)
        end
        module_function :replace

        # @rbs (SyntaxNode previous, GreenNode green) -> SyntaxNode
        def red_root(previous, green)
          source = SourceText.new(green.to_source, file: previous.source_text.file)
          SyntaxNode.new(
            green: green, kinds: previous.kinds, trivia_policy: previous.trivia_policy,
            source_text: source
          )
        end
        module_function :red_root

        # @rbs (green | element value) -> green
        def green_element(value)
          return value.green if value.is_a?(SyntaxNode) || value.is_a?(SyntaxToken)
          return value if value.is_a?(GreenNode) || value.is_a?(GreenToken)

          raise TypeError, "replacement must be a Green syntax element or Red syntax view"
        end
        module_function :green_element
      end
    end
  end
end
