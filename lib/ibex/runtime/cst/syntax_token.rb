# frozen_string_literal: true
# rbs_inline: enabled

require_relative "green/token" unless defined?(Ibex::Runtime::CST::GreenToken)

module Ibex
  module Runtime
    module CST
      # Raised when source-coordinate APIs are used on a trivia-dropped tree.
      class TriviaDroppedError < StandardError; end

      # Lightweight Red facade for one Green token occurrence.
      class SyntaxToken
        attr_reader :green #: GreenToken
        attr_reader :parent #: SyntaxNode
        attr_reader :index #: Integer
        attr_reader :offset #: Integer

        # @rbs (green: GreenToken, parent: SyntaxNode, index: Integer, offset: Integer) -> void
        def initialize(green:, parent:, index:, offset:)
          @green = green
          @parent = parent
          @index = index
          @offset = offset
          freeze
        end

        # @rbs () -> Integer
        def kind = @green.kind

        # @rbs () -> String
        def kind_name = @parent.kinds.name(kind)

        # @rbs () -> String
        def symbol = kind_name

        # @rbs () -> String
        def text = @green.text

        # @rbs () -> String
        def full_text = @green.to_source
        alias to_source full_text

        # @rbs () -> Range[Integer]
        def full_span
          ensure_coordinates!
          @offset...(@offset + @green.full_width)
        end

        # @rbs () -> Range[Integer]
        def span
          ensure_coordinates!
          (@offset + @green.leading_width)...(@offset + @green.full_width - @green.trailing_width)
        end

        # @rbs () -> Ibex::Location
        def location = @parent.source_text.location(span)

        # @rbs () -> bool
        def error? = @parent.kinds.error?(kind)

        # @rbs () -> bool
        def missing? = @green.flags.anybits?(Flags::CONTAINS_MISSING)

        # @rbs () -> bool
        def contains_error? = @green.flags.anybits?(Flags::CONTAINS_ERROR)

        # @rbs () -> (SyntaxNode | SyntaxToken)?
        def next_sibling = @parent.children[@index + 1]

        # @rbs () -> (SyntaxNode | SyntaxToken)?
        def prev_sibling
          return if @index.zero?

          @parent.children[@index - 1]
        end

        # @rbs () -> SyntaxNode
        def root = @parent.root

        # @rbs (SyntaxToken other) -> bool
        def same_node?(other)
          root.equal?(other.root) && @green.equal?(other.green) && @offset == other.offset
        end

        # @rbs (untyped other) -> bool
        def ==(other)
          other.is_a?(SyntaxToken) && @green == other.green
        end

        # @rbs () -> Array[untyped]
        def deconstruct = []

        # @rbs (Array[Symbol]?) -> Hash[Symbol, untyped]
        def deconstruct_keys(_keys)
          {
            kind: :token, symbol: symbol, text: text, location: location,
            leading_trivia: @green.leading
          }.freeze
        end

        private

        # @rbs () -> void
        def ensure_coordinates!
          return unless @parent.trivia_policy == :drop

          raise TriviaDroppedError, "source coordinates are unavailable when CST trivia is dropped"
        end
      end
    end
  end
end
