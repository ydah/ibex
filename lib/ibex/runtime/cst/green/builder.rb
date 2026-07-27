# frozen_string_literal: true
# rbs_inline: enabled

require_relative "cache" unless defined?(Ibex::Runtime::CST::NodeCache)

module Ibex
  module Runtime
    module CST
      # LR bottom-up builder backed by a Green element stack.
      # rubocop:disable Naming/PredicateMethod -- mutation methods report whether they found a target.
      class GreenBuilder
        # @rbs! type child = GreenNode | GreenToken

        # @rbs @kinds: Kind
        # @rbs @cache: NodeCache
        # @rbs @stack: Array[child]

        # @rbs (kinds: Kind, ?cache: NodeCache) -> void
        def initialize(kinds:, cache: NodeCache.new)
          @kinds = kinds
          @cache = cache
          @stack = []
        end

        # @rbs (Integer kind, String text, ?leading: Array[GreenTrivia], ?trailing: Array[GreenTrivia],
        #   ?flags: Integer) -> GreenToken
        def token(kind, text, leading: [], trailing: [], flags: 0)
          value = make_token(kind, text, leading: leading, trailing: trailing, flags: flags)
          @stack << value
          value
        end

        # Construct an interned token without changing the builder stack.
        # @rbs (Integer kind, String text, ?leading: Array[GreenTrivia], ?trailing: Array[GreenTrivia],
        #   ?flags: Integer) -> GreenToken
        def make_token(kind, text, leading: [], trailing: [], flags: 0)
          @cache.intern_token(
            GreenToken.new(kind: kind, text: text, leading: leading, trailing: trailing, flags: flags)
          )
        end

        # @rbs (Integer kind, Integer arity, ?flags: Integer) -> GreenNode
        def node(kind, arity, flags: 0)
          raise ArgumentError, "arity must be non-negative" if arity.negative?
          raise ArgumentError, "green stack underflow" if arity > @stack.length

          empty = [] #: Array[child]
          children = arity.zero? ? empty : @stack.pop(arity)
          value = @cache.intern_node(GreenNode.new(kind: kind, children: children, flags: flags))
          @stack << value
          value
        end

        # @rbs (Integer expected_kind) -> GreenToken
        def missing(expected_kind)
          value = @cache.intern_token(
            GreenToken.missing(kind: @kinds.fetch(:missing_token), expected_kind: expected_kind)
          )
          @stack << value
          value
        end

        # @rbs (String text, ?leading: Array[GreenTrivia]) -> GreenToken
        def lexical_error(text, leading: [])
          value = @cache.intern_token(
            GreenToken.lexical_error(kind: @kinds.fetch(:lexical_error_token), text: text, leading: leading)
          )
          @stack << value
          value
        end

        # Preserve popped and discarded Green elements in one error node.
        # @rbs (Integer pop_count, ?skipped: Array[child]) -> GreenNode
        def absorb_into_error(pop_count, skipped: [])
          raise ArgumentError, "pop_count must be non-negative" if pop_count.negative?
          raise ArgumentError, "green stack underflow" if pop_count > @stack.length

          empty = [] #: Array[child]
          popped = pop_count.zero? ? empty : @stack.pop(pop_count)
          value = @cache.intern_node(
            GreenNode.new(
              kind: @kinds.fetch(:error_node), children: popped + skipped,
              flags: Flags::CONTAINS_ERROR
            )
          )
          @stack << value
          value
        end

        # Wrap the completed start node and explicit EOF token.
        # @rbs (GreenToken eof_token, ?incomplete: bool) -> GreenNode
        def finish_source_file(eof_token, incomplete: false)
          raise ArgumentError, "expected one completed start node" unless @stack.one?

          flags = Flags::SYNTHETIC
          flags |= Flags::INCOMPLETE_INPUT if incomplete
          @cache.intern_node(
            GreenNode.new(
              kind: @kinds.fetch(:source_file), children: [@stack.fetch(0), eof_token],
              flags: flags
            )
          )
        end

        # Preserve every available fragment when parsing terminates without a start node.
        # @rbs (?Array[child] trailing, ?incomplete: bool) -> GreenNode
        def finish_synthetic_root(trailing = [], incomplete: false)
          flags = Flags::SYNTHETIC | Flags::CONTAINS_ERROR
          flags |= Flags::INCOMPLETE_INPUT if incomplete
          @cache.intern_node(
            GreenNode.new(
              kind: @kinds.fetch(:synthetic_root), children: @stack + trailing,
              flags: flags
            )
          )
        end

        # Append discarded input to the most recent error node on the stack.
        # @rbs (child skipped) -> bool
        def append_to_last_error(skipped)
          index = @stack.rindex { |element| element.is_a?(GreenNode) && element.kind == @kinds.fetch(:error_node) }
          return false unless index

          error = @stack.fetch(index)
          return false unless error.is_a?(GreenNode)

          @stack[index] = @cache.intern_node(
            GreenNode.new(
              kind: error.kind, children: error.children + [skipped],
              flags: error.flags | Flags::CONTAINS_ERROR
            )
          )
          true
        end

        # Path-copy the right edge to attach balanced trailing trivia.
        # @rbs (Array[GreenTrivia] trivia) -> bool
        def append_trailing_to_last_token(trivia)
          return false if trivia.empty?

          index = @stack.length - 1
          while index >= 0
            replacement = with_rightmost_trailing(@stack.fetch(index), trivia)
            if replacement
              @stack[index] = replacement
              return true
            end
            index -= 1
          end
          false
        end

        # @rbs () -> Array[child]
        def snapshot = @stack.dup

        # @rbs (Array[child] elements) -> void
        def restore(elements)
          @stack = elements.dup
        end

        # @rbs () -> Integer
        def size = @stack.length

        # @rbs () -> Array[child]
        def elements = @stack.dup.freeze

        private

        # @rbs (child element, Array[GreenTrivia] trivia) -> child?
        def with_rightmost_trailing(element, trivia)
          if element.is_a?(GreenToken)
            return @cache.intern_token(
              GreenToken.new(
                kind: element.kind, text: element.text, leading: element.leading,
                trailing: element.trailing + trivia, flags: element.flags,
                expected_kind: element.expected_kind
              )
            )
          end
          return if element.children.empty?

          child = element.children.last
          return unless child

          replacement = with_rightmost_trailing(child, trivia)
          return unless replacement

          children = element.children.dup
          children[-1] = replacement
          @cache.intern_node(GreenNode.new(kind: element.kind, children: children, flags: element.flags))
        end
      end
      # rubocop:enable Naming/PredicateMethod
    end
  end
end
