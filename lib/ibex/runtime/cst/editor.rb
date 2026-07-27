# frozen_string_literal: true
# rbs_inline: enabled

require_relative "editing" unless defined?(Ibex::Runtime::CST::Editing)

module Ibex
  module Runtime
    module CST
      class EditConflictError < StandardError; end

      # Applies multiple occurrence-addressed replacements in one path-copying pass.
      class SyntaxEditor
        # @rbs! type element = SyntaxNode | SyntaxToken
        # @rbs! type green = GreenNode | GreenToken
        # @rbs! type edit = [element, green]

        # @rbs @root: SyntaxNode
        # @rbs @edits: Array[edit]

        # @rbs (SyntaxNode root) -> void
        def initialize(root)
          @root = root
          @edits = []
        end

        # @rbs (element target, green | element replacement) -> self
        def replace(target, replacement)
          raise ArgumentError, "edit target belongs to a different root" unless target.root.equal?(@root)

          green = Editing.green_element(replacement)
          duplicate = @edits.find { |existing, _value| same_occurrence?(existing, target) }
          if duplicate
            raise EditConflictError, "the same syntax occurrence has conflicting replacements" unless
              duplicate.fetch(1).equal?(green)

            return self
          end
          return self if @edits.any? { |existing, _value| ancestor?(existing, target) }

          @edits.reject! { |existing, _value| ancestor?(target, existing) }
          @edits << [target, green]
          self
        end

        # @rbs () -> SyntaxNode
        def apply
          green = apply_element(@root)
          return @root if green.equal?(@root.green)
          raise TypeError, "a syntax root must remain a GreenNode" unless green.is_a?(GreenNode)

          Editing.red_root(@root, green)
        end

        private

        # @rbs (element element) -> green
        def apply_element(element)
          replacement = @edits.find { |target, _green| same_occurrence?(target, element) }&.fetch(1)
          return replacement if replacement
          return element.green if element.is_a?(SyntaxToken)

          changed = false
          children = element.children.map do |child|
            green = apply_element(child)
            changed ||= !green.equal?(child.green)
            green
          end
          return element.green unless changed

          GreenNode.new(
            kind: element.green.kind, children: children,
            flags: element.green.intrinsic_flags, annotations: element.green.annotations
          )
        end

        # @rbs (element possible_ancestor, element element) -> bool
        def ancestor?(possible_ancestor, element)
          parent = element.parent
          while parent
            return true if same_occurrence?(parent, possible_ancestor)

            parent = parent.parent
          end
          false
        end

        # @rbs (element left, element right) -> bool
        def same_occurrence?(left, right)
          left.root.equal?(right.root) && left.green.equal?(right.green) && left.offset == right.offset
        end
      end
    end
  end
end
