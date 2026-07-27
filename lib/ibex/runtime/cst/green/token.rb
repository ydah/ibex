# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../kind" unless defined?(Ibex::Runtime::CST::Flags)
require_relative "trivia" unless defined?(Ibex::Runtime::CST::GreenTrivia)

module Ibex
  module Runtime
    module CST
      # Immutable position-independent terminal occurrence.
      class GreenToken
        attr_reader :kind #: Integer
        attr_reader :text #: String
        attr_reader :leading #: Array[GreenTrivia]
        attr_reader :trailing #: Array[GreenTrivia]
        attr_reader :flags #: Integer
        attr_reader :full_width #: Integer
        attr_reader :leading_width #: Integer
        attr_reader :trailing_width #: Integer
        attr_reader :expected_kind #: Integer?

        # @rbs (kind: Integer, text: String, ?leading: Array[GreenTrivia], ?trailing: Array[GreenTrivia],
        #   ?flags: Integer, ?expected_kind: Integer?) -> void
        def initialize(kind:, text:, leading: [], trailing: [], flags: 0, expected_kind: nil)
          @kind = kind
          @text = text.b.freeze
          @leading = leading.dup.freeze
          @trailing = trailing.dup.freeze
          @flags = flags
          @expected_kind = expected_kind
          @leading_width = trivia_width(@leading)
          @trailing_width = trivia_width(@trailing)
          @full_width = @leading_width + @text.bytesize + @trailing_width
          freeze
        end

        # @rbs (kind: Integer, expected_kind: Integer) -> GreenToken
        def self.missing(kind:, expected_kind:)
          new(
            kind: kind, text: "", expected_kind: expected_kind,
            flags: Flags::CONTAINS_MISSING | Flags::SYNTHETIC
          )
        end

        # @rbs (kind: Integer, text: String, ?leading: Array[GreenTrivia]) -> GreenToken
        def self.lexical_error(kind:, text:, leading: [])
          new(kind: kind, text: text, leading: leading, flags: Flags::CONTAINS_ERROR)
        end

        # @rbs () -> Integer
        def descendant_count = 1

        # @rbs () -> String
        def to_source
          source = String.new(encoding: Encoding::BINARY)
          @leading.each { |trivia| source << trivia.text }
          source << @text
          @trailing.each { |trivia| source << trivia.text }
          source
        end

        # @rbs (untyped other) -> bool
        def ==(other)
          other.is_a?(GreenToken) &&
            [@kind, @text, @leading, @trailing, @flags, @expected_kind] ==
              [other.kind, other.text, other.leading, other.trailing, other.flags, other.expected_kind]
        end
        alias eql? ==

        # @rbs () -> Integer
        def hash = [@kind, @text, @leading, @trailing, @flags, @expected_kind].hash

        private

        # @rbs (Array[GreenTrivia] trivia) -> Integer
        def trivia_width(trivia)
          trivia.sum(&:full_width)
        end
      end
    end
  end
end
