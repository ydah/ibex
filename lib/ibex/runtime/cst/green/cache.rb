# frozen_string_literal: true
# rbs_inline: enabled

require_relative "node" unless defined?(Ibex::Runtime::CST::GreenNode)

module Ibex
  module Runtime
    module CST
      # Session-owned hash-consing cache for immutable Green elements.
      class NodeCache
        DEFAULT_NODE_ARITY_LIMIT = 3 #: Integer
        DEFAULT_NODE_DESCENDANT_LIMIT = 32 #: Integer
        empty_trivia = [] # @type var empty_trivia: Array[GreenTrivia]
        EMPTY_TRIVIA = empty_trivia.freeze #: Array[GreenTrivia]

        # @rbs @enabled: bool
        # @rbs @node_arity_limit: Integer
        # @rbs @node_descendant_limit: Integer
        # @rbs @trivia: Hash[Integer, Array[GreenTrivia]]
        # @rbs @tokens: Hash[Integer, Array[GreenToken]]
        # @rbs @nodes: Hash[GreenNode, GreenNode]

        # @rbs (?enabled: bool, ?node_arity_limit: Integer, ?node_descendant_limit: Integer) -> void
        def initialize(
          enabled: true, node_arity_limit: DEFAULT_NODE_ARITY_LIMIT,
          node_descendant_limit: DEFAULT_NODE_DESCENDANT_LIMIT
        )
          raise ArgumentError, "node_arity_limit must be non-negative" if node_arity_limit.negative?
          raise ArgumentError, "node_descendant_limit must be positive" unless node_descendant_limit.positive?

          @enabled = enabled
          @node_arity_limit = node_arity_limit
          @node_descendant_limit = node_descendant_limit
          @trivia = {}
          @tokens = {}
          @nodes = {}
        end

        # Intern trivia before constructing it, using byte-equivalent text within this session.
        # @rbs (kind: Integer, text: String) -> GreenTrivia
        def intern_trivia_fields(kind:, text:)
          return GreenTrivia.new(kind: kind, text: text) unless @enabled

          comparable_text = if text.encoding == Encoding::BINARY || text.ascii_only?
                              text
                            else
                              text.b.freeze
                            end
          signature = kind.hash ^ comparable_text.hash
          bucket = @trivia[signature]
          existing = bucket&.find { |trivia| trivia.kind == kind && trivia.text == comparable_text }
          return existing if existing

          trivia = GreenTrivia.new(kind: kind, text: comparable_text)
          (@trivia[signature] ||= []) << trivia
          trivia
        end

        # @rbs (GreenToken token) -> GreenToken
        def intern_token(token)
          return token unless @enabled
          return token unless token.flags.nobits?(Flags::HAS_ANNOTATION)

          signature = token_signature(
            token.kind, token.text, token.leading, token.trailing, token.flags, token.expected_kind
          )
          bucket = @tokens[signature]
          existing = find_token(
            bucket, token.kind, token.text, token.leading, token.trailing, token.flags, token.expected_kind
          )
          return existing if existing

          (@tokens[signature] ||= []) << token
          token
        end

        # Intern a token before constructing it, avoiding discarded duplicate immutable values.
        # @rbs (kind: Integer, text: String, ?leading: Array[GreenTrivia], ?trailing: Array[GreenTrivia],
        #   ?flags: Integer, ?expected_kind: Integer?) -> GreenToken
        def intern_token_fields(
          kind:, text:, leading: EMPTY_TRIVIA, trailing: EMPTY_TRIVIA, flags: 0, expected_kind: nil
        )
          unless @enabled && flags.nobits?(Flags::HAS_ANNOTATION)
            return GreenToken.new(
              kind: kind, text: text, leading: leading, trailing: trailing,
              flags: flags, expected_kind: expected_kind
            )
          end

          comparable_text = if text.encoding == Encoding::BINARY || text.ascii_only?
                              text
                            else
                              text.b.freeze
                            end
          signature = token_signature(kind, comparable_text, leading, trailing, flags, expected_kind)
          bucket = @tokens[signature]
          existing = find_token(bucket, kind, comparable_text, leading, trailing, flags, expected_kind)
          return existing if existing

          token = GreenToken.new(
            kind: kind, text: comparable_text, leading: leading, trailing: trailing,
            flags: flags, expected_kind: expected_kind
          )
          (@tokens[signature] ||= []) << token
          token
        end

        # @rbs (GreenNode node) -> GreenNode
        def intern_node(node)
          return node unless @enabled
          return node if node.children.length > @node_arity_limit
          return node if node.descendant_count > @node_descendant_limit
          return node unless node.flags.nobits?(Flags::HAS_ANNOTATION)

          @nodes[node] ||= node
        end

        # @rbs () -> void
        def clear
          @trivia.clear
          @tokens.clear
          @nodes.clear
        end

        private

        # @rbs (Integer kind, String text, Array[GreenTrivia] leading, Array[GreenTrivia] trailing,
        #   Integer flags, Integer? expected_kind) -> Integer
        def token_signature(kind, text, leading, trailing, flags, expected_kind)
          kind.hash ^ text.hash ^ leading.hash ^ trailing.hash ^ flags.hash ^ expected_kind.hash
        end

        # @rbs (Array[GreenToken]? bucket, Integer kind, String text, Array[GreenTrivia] leading,
        #   Array[GreenTrivia] trailing, Integer flags, Integer? expected_kind) -> GreenToken?
        def find_token(bucket, kind, text, leading, trailing, flags, expected_kind)
          return unless bucket

          bucket.find do |token|
            token.kind == kind &&
              token.text == text &&
              token.leading == leading &&
              token.trailing == trailing &&
              token.flags == flags &&
              token.expected_kind == expected_kind
          end
        end
      end
    end
  end
end
