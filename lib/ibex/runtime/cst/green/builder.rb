# frozen_string_literal: true
# rbs_inline: enabled

require_relative "cache" unless defined?(Ibex::Runtime::CST::NodeCache)

module Ibex
  module Runtime
    module CST
      # LR bottom-up builder backed by a Green element stack.
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
          value = @cache.intern_token(
            GreenToken.new(kind: kind, text: text, leading: leading, trailing: trailing, flags: flags)
          )
          @stack << value
          value
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

        # @rbs () -> Integer
        def size = @stack.length

        # @rbs () -> Array[child]
        def elements = @stack.dup.freeze
      end
    end
  end
end
