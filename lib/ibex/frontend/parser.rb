# frozen_string_literal: true

module Ibex
  module Frontend
    # Public grammar parser backed by Ibex's generated LR frontend.
    class Parser
      attr_reader :implementation #: GeneratedParser

      # @rbs (String | Array[Token] source, ?file: String, ?mode: Symbol) -> void
      def initialize(source, file: "(grammar)", mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        tokens = source.is_a?(Array) ? source : Lexer.new(source, file: file).tokenize
        @implementation = GeneratedParser.new(tokens, mode: mode)
      end

      # @rbs () -> AST::Root
      def parse
        @implementation.parse
      end
    end
  end
end
