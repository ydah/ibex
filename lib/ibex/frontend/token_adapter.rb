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

      attr_reader :conversion_name, :declaration, :eof_token, :group_opening, :last_token,
                  :precedence_closer, :previous_external, :section

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

        external = external_type(token)
        track_structure(token, external)
        [external, token]
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
        type = :IDENTIFIER if %i[LEFT RIGHT NONASSOC].include?(type) && @declaration != :precedence
        type = :IDENTIFIER if type == :END && @declaration != :convert
        track_declaration(type)
        @section = :rules if type == :RULE
        type
      end

      def track_declaration(type)
        if %i[PRECHIGH PRECLOW].include?(type)
          if @declaration == :precedence
            @declaration = nil
            @precedence_closer = nil
          else
            @declaration = :precedence
            @precedence_closer = type == :PRECHIGH ? "preclow" : "prechigh"
          end
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
        type = nil if %i[SEPARATED_LIST SEPARATED_NONEMPTY_LIST].include?(type) && !separated_list_call?
        type = nil if type == :END && named_reference_name?
        @section = :user_code if type == :END
        type || :IDENTIFIER
      end

      def separated_list_call?
        @tokens.fetch(@index, @tokens.last).type == :"("
      end

      def named_reference_name?
        @last_external == ":" && %i[IDENTIFIER LITERAL].include?(@previous_external)
      end

      def rule_lhs?(token)
        return false if token.value == "end"
        return true if @lhs_column.nil?

        following = @tokens.fetch(@index, @tokens.last)
        return false unless following.type == :":"

        token.location.column <= @lhs_column
      end

      def track_structure(token, external)
        track_conversion(token, external)
        track_groups(token, external) if @section == :rules
        @previous_external = @last_external
        @last_external = external
      end

      def track_conversion(token, external)
        return unless @declaration == :convert
        return unless %i[IDENTIFIER LITERAL].include?(external)

        validate_conversion_line(token) unless @conversion_name
        @conversion_name ||= token
        @conversion_name = nil if @conversion_name != token && external == :LITERAL
      end

      def validate_conversion_line(name)
        line = name.location.line
        following = @tokens[@index..].take_while do |token|
          token.type != :eof && token.location.line == line && !(token.type == :identifier && token.value == "end")
        end
        return if following.length == 1 && following.first.type == :literal

        raise Ibex::Error, "#{name.location}: expected a quoted Ruby conversion expression"
      end

      def track_groups(token, external)
        @group_openings ||= []
        separated = %i[SEPARATED_LIST SEPARATED_NONEMPTY_LIST].include?(@last_external)
        @group_openings << token if external == "(" && !separated
        @group_openings.pop if external == ")" && @group_openings.any?
        @group_opening = @group_openings.last
      end
    end
  end
end
