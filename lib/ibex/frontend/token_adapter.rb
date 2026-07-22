# frozen_string_literal: true

module Ibex
  module Frontend
    # Adapts location-bearing lexer tokens to the self-hosted parser terminals.
    class TokenAdapter
      DECLARATION_KEYWORDS = {
        "class" => :CLASS, "token" => :TOKEN, "prechigh" => :PRECHIGH, "preclow" => :PRECLOW,
        "options" => :OPTIONS, "expect" => :EXPECT, "start" => :START, "convert" => :CONVERT,
        "rule" => :RULE, "end" => :END, "left" => :LEFT, "right" => :RIGHT,
        "nonassoc" => :NONASSOC
      }.freeze
      RULE_KEYWORDS = {
        "end" => :END, "separated_list" => :SEPARATED_LIST,
        "separated_nonempty_list" => :SEPARATED_NONEMPTY_LIST
      }.freeze
      TOKEN_TYPES = {
        identifier: :IDENTIFIER, literal: :LITERAL, integer: :INTEGER,
        action: :ACTION, user_code: :USER_CODE
      }.freeze

      attr_reader :declaration, :eof_token, :last_token, :section

      def initialize(tokens)
        @tokens = tokens
        @index = 0
        @section = :declarations
        @lhs_column = nil
      end

      def next_token
        token = @tokens.fetch(@index)
        @index += 1
        @last_token = token
        if token.type == :eof
          @eof_token = token
          return false
        end

        [external_type(token), token]
      end

      private

      def external_type(token)
        return token.value if punctuation?(token)
        return TOKEN_TYPES.fetch(token.type) unless token.type == :identifier

        @section == :rules ? rule_identifier_type(token) : declaration_identifier_type(token)
      end

      def punctuation?(token)
        !%i[identifier literal integer action user_code eof].include?(token.type)
      end

      def declaration_identifier_type(token)
        type = DECLARATION_KEYWORDS[token.value] || :IDENTIFIER
        track_declaration(type)
        @section = :rules if type == :RULE
        type
      end

      def track_declaration(type)
        if %i[PRECHIGH PRECLOW].include?(type)
          @declaration = @declaration == :precedence ? nil : :precedence
        end
        @declaration = type.downcase if %i[TOKEN OPTIONS EXPECT START CONVERT].include?(type)
        @declaration = nil if type == :RULE
      end

      def rule_identifier_type(token)
        if rule_lhs?(token)
          @lhs_column = token.location.column
          return :LHS
        end

        type = RULE_KEYWORDS[token.value]
        @section = :user_code if type == :END
        type || :IDENTIFIER
      end

      def rule_lhs?(token)
        following = @tokens.fetch(@index, @tokens.last)
        return false unless following.type == :":"

        @lhs_column.nil? || token.location.column <= @lhs_column
      end
    end
  end
end
