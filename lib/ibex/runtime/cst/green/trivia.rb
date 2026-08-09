# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Immutable source text ignored by the grammar but owned by a token.
      class GreenTrivia
        attr_reader :kind #: Integer
        attr_reader :text #: String
        attr_reader :full_width #: Integer
        attr_reader :hash #: Integer

        # @rbs (kind: Integer, text: String) -> void
        def initialize(kind:, text:)
          @kind = kind
          @text = text.b.freeze
          @full_width = @text.bytesize
          @hash = [@kind, @text].hash
          freeze
        end

        # @rbs () -> String
        def to_source = @text

        # @rbs (Object? other) -> bool
        def ==(other)
          other.is_a?(GreenTrivia) && @kind == other.kind && @text == other.text
        end
        alias eql? ==

        # @rbs () -> Integer
      end
    end
  end
end
