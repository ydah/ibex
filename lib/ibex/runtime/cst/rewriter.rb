# frozen_string_literal: true
# rbs_inline: enabled

require_relative "editing" unless defined?(Ibex::Runtime::CST::Editing)

module Ibex
  module Runtime
    module CST
      # Bottom-up syntax rewriter with kind-name dispatch.
      class SyntaxRewriter
        # @rbs! type element = SyntaxNode | SyntaxToken
        # @rbs! type green = GreenNode | GreenToken

        # @rbs (SyntaxNode root) -> SyntaxNode
        def rewrite(root)
          green = visit(root)
          return root if green.equal?(root.green)
          raise TypeError, "a syntax root must remain a GreenNode" unless green.is_a?(GreenNode)

          Editing.red_root(root, green)
        end

        # @rbs (element element) -> green
        def visit(element)
          rewritten = element.is_a?(SyntaxNode) ? visit_children(element) : element.green
          method = :"visit_#{method_name(element.kind_name)}"
          return rewritten unless respond_to?(method, true)

          Editing.green_element(__send__(method, rewritten_view(element, rewritten)))
        end

        private

        # @rbs (SyntaxNode node) -> GreenNode
        def visit_children(node)
          changed = false
          children = node.children.map do |child|
            green = visit(child)
            changed ||= !green.equal?(child.green)
            green
          end
          return node.green unless changed

          GreenNode.new(
            kind: node.green.kind, children: children,
            flags: node.green.intrinsic_flags, annotations: node.green.annotations
          )
        end

        # @rbs (element original, green rewritten) -> element
        def rewritten_view(original, rewritten)
          if rewritten.is_a?(GreenNode)
            raise TypeError, "a node rewrite requires its original node" unless original.is_a?(SyntaxNode)

            source = SourceText.new(rewritten.to_source, file: original.root.source_text.file)
            return SyntaxNode.new(
              green: rewritten, kinds: original.kinds,
              trivia_policy: original.root.trivia_policy, source_text: source
            )
          end

          parent = original.parent
          raise TypeError, "a token rewrite requires its original parent" unless parent

          SyntaxToken.new(green: rewritten, parent: parent, index: original.index, offset: original.offset)
        end

        # @rbs (String name) -> String
        def method_name(name)
          name.gsub(/[^a-zA-Z0-9_]/, "_")
        end
      end
    end
  end
end
