# frozen_string_literal: true

module Ibex
  module Frontend
    # Public grammar parser backed by Ibex's generated LR frontend.
    class Parser
      attr_reader :implementation

      def initialize(source, file: "(grammar)", mode: :racc)
        tokens = source.is_a?(Array) ? source : Lexer.new(source, file: file).tokenize
        @implementation = GeneratedParser.new(tokens, mode: mode)
      end

      def parse
        @implementation.parse
      end
    end
  end
end
