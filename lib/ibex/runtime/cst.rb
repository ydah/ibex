# frozen_string_literal: true
# rbs_inline: enabled

require_relative "cst/kind" unless defined?(Ibex::Runtime::CST::Kind)
require_relative "cst/green/trivia" unless defined?(Ibex::Runtime::CST::GreenTrivia)
require_relative "cst/green/token" unless defined?(Ibex::Runtime::CST::GreenToken)
require_relative "cst/green/node" unless defined?(Ibex::Runtime::CST::GreenNode)
require_relative "cst/green/cache" unless defined?(Ibex::Runtime::CST::NodeCache)
require_relative "cst/green/builder" unless defined?(Ibex::Runtime::CST::GreenBuilder)

module Ibex
  module Runtime
    # Immutable concrete syntax tree values produced by `pragma cst` parsers.
    module CST
      # Ignored lexer text retained by the attach trivia policy.
      class Trivia
        attr_reader :text #: String
        attr_reader :location #: untyped

        # @rbs (text: String, location: untyped) -> void
        def initialize(text:, location:)
          @text = text.dup.freeze
          @location = location
          freeze
        end

        # @rbs () -> Hash[Symbol, untyped]
        def to_h = { kind: :trivia, text: @text, location: @location }.freeze
      end

      # A terminal occurrence in source order.
      class Token
        attr_reader :symbol #: String
        attr_reader :value #: untyped
        attr_reader :location #: untyped
        attr_reader :leading_trivia #: Array[Trivia]

        # @rbs (symbol: String, value: untyped, location: untyped, ?leading_trivia: Array[Trivia]) -> void
        def initialize(symbol:, value:, location:, leading_trivia: [])
          @symbol = symbol.dup.freeze
          @value = value
          @location = location
          @leading_trivia = leading_trivia.dup.freeze
          freeze
        end

        # @rbs () -> Symbol
        def kind = :token

        # @rbs () -> Array[untyped]
        def children = []

        # @rbs () -> Array[untyped]
        def deconstruct = []

        # @rbs (Array[Symbol]?) -> Hash[Symbol, untyped]
        def deconstruct_keys(_keys)
          { kind: kind, symbol: @symbol, value: @value, location: @location,
            leading_trivia: @leading_trivia }.freeze
        end

        # @rbs () -> Hash[Symbol, untyped]
        def to_h = deconstruct_keys(nil)
      end

      # A token synthesized by bounded repair.
      class Missing < Token
        # @rbs () -> Symbol
        def kind = :missing
      end

      # Invalid or discarded source retained in an error-tolerant tree.
      class Error < Token
        attr_reader :reason #: Symbol

        # @rbs (symbol: String, value: untyped, location: untyped, ?reason: Symbol,
        #   ?leading_trivia: Array[Trivia]) -> void
        def initialize(symbol:, value:, location:, reason: :syntax, leading_trivia: [])
          @reason = reason
          super(symbol: symbol, value: value, location: location, leading_trivia: leading_trivia)
        end

        # @rbs () -> Symbol
        def kind = :error

        # @rbs (Array[Symbol]?) -> Hash[Symbol, untyped]
        def deconstruct_keys(keys)
          super.merge(reason: @reason).freeze
        end
      end

      # A reduced nonterminal and its source-ordered children.
      class Node
        # @rbs! include Enumerable[Token | Node]
        # @rbs skip
        include Enumerable

        attr_reader :symbol #: String
        attr_reader :production_id #: Integer
        attr_reader :children #: Array[Token | Node]
        attr_reader :location #: untyped
        attr_reader :trailing_trivia #: Array[Trivia]

        # @rbs (symbol: String, production_id: Integer, children: Array[Token | Node],
        #   location: untyped, ?trailing_trivia: Array[Trivia]) -> void
        def initialize(symbol:, production_id:, children:, location:, trailing_trivia: [])
          @symbol = symbol.dup.freeze
          @production_id = production_id
          @children = children.dup.freeze
          @location = location
          @trailing_trivia = trailing_trivia.dup.freeze
          freeze
        end

        # @rbs () -> Symbol
        def kind = :node

        # @rbs!
        #   def each: () -> Enumerator[Token | Node, Node]
        #           | () { (Token | Node) -> void } -> Node
        # @rbs skip
        def each(&block)
          return enum_for(:each) unless block

          @children.each(&block)
          self
        end

        # @rbs () -> Array[Token | Node]
        def deconstruct = @children

        # @rbs (Array[Symbol]?) -> Hash[Symbol, untyped]
        def deconstruct_keys(_keys)
          { kind: kind, symbol: @symbol, production_id: @production_id, children: @children,
            location: @location, trailing_trivia: @trailing_trivia }.freeze
        end

        # @rbs () -> Hash[Symbol, untyped]
        def to_h = deconstruct_keys(nil)

        # @rbs (Array[Trivia]) -> Node
        def with_trailing_trivia(trivia)
          self.class.new(
            symbol: @symbol, production_id: @production_id, children: @children,
            location: @location, trailing_trivia: trivia
          )
        end
      end
    end
  end
end
