# frozen_string_literal: true

module Ibex
  module Frontend
    # Delivers lexer tokens through declaration and rule context classifiers.
    class TokenAdapter
      attr_reader :eof_token #: Token?
      attr_reader :last_token #: Token?
      attr_reader :previous_external #: external_token?

      # @rbs @tokens: Array[Token]
      # @rbs @index: Integer
      # @rbs @declarations: DeclarationState
      # @rbs @classifier: DeclarationState | RuleState
      # @rbs @rules: RuleState?
      # @rbs @last_external: external_token?

      # @rbs (Array[Token] tokens) -> void
      def initialize(tokens)
        @tokens = tokens
        @index = 0
        @declarations = DeclarationState.new
        @classifier = @declarations
      end

      # @rbs () -> ([external_token, Token] | false)
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

      # @rbs () -> Token?
      def conversion_name
        @declarations.conversion_name
      end

      # @rbs () -> Symbol?
      def declaration
        @declarations.declaration
      end

      # @rbs () -> String?
      def precedence_closer
        @declarations.precedence_closer
      end

      # @rbs () -> parser_section
      def section
        rules = @rules
        rules ? rules.section : :declarations
      end

      # @rbs () -> Symbol
      def state
        @classifier.state
      end

      # @rbs () -> Token?
      def group_opening
        @rules&.group_opening
      end

      # @rbs () -> delimiter_kind?
      def open_delimiter_kind
        @rules&.open_delimiter_kind
      end

      # @rbs (Token? token) -> String?
      def expectation(token)
        @classifier.expectation(token)
      end

      private

      # @rbs (Token token) -> external_token
      def classify(token)
        remaining = @tokens.drop(@index)
        rules = @rules
        return @declarations.classify(token, remaining) unless rules

        rules.classify(token, remaining, last_external: @last_external,
                                         previous_external: @previous_external)
      end

      # @rbs () -> void
      def enter_rules
        @rules = RuleState.new
        @classifier = @rules
      end
    end
  end
end
