# frozen_string_literal: true

module Ibex
  module Frontend
    # Delivers lexer tokens through declaration and rule context classifiers.
    class TokenAdapter
      attr_reader :eof_token, :last_token, :previous_external

      def initialize(tokens)
        @tokens = tokens
        @index = 0
        @declarations = DeclarationState.new
        @classifier = @declarations
      end

      def next_token
        token = @tokens.fetch(@index)
        @index += 1
        @last_token = token
        if token.type == :eof
          @eof_token = token
          return false
        end

        external = classify(token)
        enter_rules if @classifier == @declarations && @declarations.rules?
        @previous_external = @last_external
        @last_external = external
        [external, token]
      end

      def conversion_name
        @declarations.conversion_name
      end

      def declaration
        @declarations.declaration
      end

      def precedence_closer
        @declarations.precedence_closer
      end

      def section
        @rules ? @rules.section : :declarations
      end

      def state
        @classifier.state
      end

      def group_opening
        @rules&.group_opening
      end

      def open_delimiter_kind
        @rules&.open_delimiter_kind
      end

      private

      def classify(token)
        remaining = @tokens[@index..]
        return @declarations.classify(token, remaining) unless @rules

        @rules.classify(token, remaining, last_external: @last_external,
                                          previous_external: @previous_external)
      end

      def enter_rules
        @rules = RuleState.new
        @classifier = @rules
      end
    end
  end
end
