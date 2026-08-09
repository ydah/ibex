# frozen_string_literal: true
# rbs_inline: enabled

require_relative "token" unless defined?(Ibex::Runtime::CST::GreenToken)

module Ibex
  module Runtime
    module CST
      # Immutable position-independent syntax node.
      class GreenNode
        # @rbs! type child = GreenNode | GreenToken

        attr_reader :kind #: Integer
        attr_reader :children #: Array[child]
        attr_reader :flags #: Integer
        attr_reader :intrinsic_flags #: Integer
        attr_reader :annotations #: Array[SyntaxAnnotation]
        attr_reader :full_width #: Integer
        attr_reader :leading_width #: Integer
        attr_reader :trailing_width #: Integer
        attr_reader :descendant_count #: Integer

        # @rbs (kind: Integer, children: Array[child], ?flags: Integer, ?annotations: Array[SyntaxAnnotation]) -> void
        def initialize(kind:, children:, flags: 0, annotations: [])
          @kind = kind
          @children = children.dup.freeze
          @annotations = annotations.dup.freeze
          @intrinsic_flags = flags
          @intrinsic_flags |= Flags::HAS_ANNOTATION unless @annotations.empty?
          @flags = @children.reduce(@intrinsic_flags) { |value, child| value | child.flags }
          @full_width = @children.sum(&:full_width)
          @leading_width = edge_width(@children, :leading_width)
          @trailing_width = edge_width(@children.reverse_each, :trailing_width)
          @descendant_count = 1 + @children.sum(&:descendant_count)
          freeze
        end

        # @rbs () -> String
        def to_source
          source = String.new(encoding: Encoding::BINARY)
          pending = @children.reverse
          until pending.empty?
            child = pending.pop || raise("green source traversal underflow")
            if child.is_a?(GreenNode)
              child.children.reverse_each { |nested| pending << nested }
              next
            end

            child.leading.each { |trivia| source << trivia.text }
            source << child.text
            child.trailing.each { |trivia| source << trivia.text }
          end
          source
        end

        # @rbs (Object? other) -> bool
        def ==(other)
          other.is_a?(GreenNode) && @kind == other.kind && @intrinsic_flags == other.intrinsic_flags &&
            @annotations == other.annotations && @children == other.children
        end
        alias eql? ==

        # @rbs () -> Integer
        def hash = [@kind, @children, @intrinsic_flags, @annotations].hash

        private

        # @rbs (Enumerable[child] children, Symbol reader) -> Integer
        def edge_width(children, reader)
          child = children.find { |candidate| candidate.full_width.positive? }
          return 0 unless child

          reader == :leading_width ? child.leading_width : child.trailing_width
        end
      end
    end
  end
end
