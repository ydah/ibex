# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Classifies context-dependent tokens in the grammar rule section.
      class RuleState
        SCALAR_TYPES = {
          literal: :LITERAL, integer: :INTEGER, action: :ACTION, user_code: :USER_CODE
        }.freeze #: Hash[Symbol, external_token]

        attr_reader :section #: parser_section
        attr_reader :state #: Symbol

        # @rbs @delimiters: DelimiterTracker
        # @rbs @lhs_column: Integer?
        # @rbs @rule_seen: bool?

        # @rbs () -> void
        def initialize
          @state = :rules_lhs
          @section = :rules
          @delimiters = DelimiterTracker.new
        end

        # @rbs (Token token, Array[Token] remaining, last_external: external_token?,
        #   previous_external: external_token?) -> external_token
        def classify(token, remaining, last_external:, previous_external:)
          external = if token.type == :identifier
                       classify_identifier(token, remaining, last_external, previous_external)
                     elsif SCALAR_TYPES.key?(token.type)
                       SCALAR_TYPES.fetch(token.type)
                     else
                       classify_punctuation(token)
                     end
          @delimiters.observe(token, external, last_external)
          external
        end

        # @rbs () -> Token?
        def group_opening
          @delimiters.group_opening
        end

        # @rbs () -> delimiter_kind?
        def open_delimiter_kind
          @delimiters.open_kind
        end

        # @rbs (Token? token) -> String?
        def expectation(token)
          if @state == :rules_lhs && @section == :rules
            rules_lhs_expectation(token)
          elsif @state == :rule_colon
            ":"
          elsif @state == :rule_rhs && %w[) ,].include?(token&.value)
            "a grammar symbol"
          end
        end

        private

        # @rbs (Token token, Array[Token] remaining, external_token? last_external,
        #   external_token? previous_external) -> external_token
        def classify_identifier(token, remaining, last_external, previous_external)
          return rule_lhs(token) if @state == :rules_lhs
          return :IDENTIFIER unless @state == :rule_rhs
          return :IDENTIFIER if named_reference_name?(last_external, previous_external)

          value = string_value(token)
          return :IDENTIFIER if value == "end" && @delimiters.open_kind == :separated
          return finish_rules if value == "end"

          following = remaining.first
          return :IDENTIFIER unless following
          return start_rule(token) if rule_boundary?(token, following)
          return separated_terminal(token) if separated_list_call?(token, following)

          :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def rule_lhs(token)
          if string_value(token) == "end"
            @section = :user_code
            return :END
          end

          @rule_seen = true
          @lhs_column = token.location.column
          @state = :rule_colon
          :LHS
        end

        # @rbs (external_token? last_external, external_token? previous_external) -> bool
        def named_reference_name?(last_external, previous_external)
          last_external == ":" && %i[IDENTIFIER LITERAL].include?(previous_external)
        end

        # @rbs (Token token, Token following) -> bool
        def rule_boundary?(token, following)
          lhs_column = @lhs_column
          return false unless lhs_column

          @delimiters.empty? && following.type == :":" && token.location.column <= lhs_column
        end

        # @rbs (Token token) -> external_token
        def start_rule(token)
          @rule_seen = true
          @lhs_column = token.location.column
          @state = :rule_colon
          :LHS
        end

        # @rbs () -> external_token
        def finish_rules
          @section = :user_code
          :END
        end

        # @rbs (Token token, Token following) -> bool
        def separated_list_call?(token, following)
          %w[separated_list separated_nonempty_list].include?(string_value(token)) && following.type == :"("
        end

        # @rbs (Token token) -> external_token
        def separated_terminal(token)
          string_value(token) == "separated_list" ? :SEPARATED_LIST : :SEPARATED_NONEMPTY_LIST
        end

        # @rbs (Token token) -> external_token
        def classify_punctuation(token)
          @state = :rule_rhs if @state == :rule_colon && token.type == :":"
          reset_rule_boundary if @state == :rule_rhs && token.type == :";" && @delimiters.empty?
          string_value(token)
        end

        # @rbs () -> void
        def reset_rule_boundary
          @lhs_column = nil
          @state = :rules_lhs
        end

        # @rbs (Token? token) -> String
        def rules_lhs_expectation(token)
          return "identifier" unless token&.type == :eof

          @rule_seen ? "end" : "at least one rule"
        end

        # @rbs (Token token) -> String
        def string_value(token)
          value = token.value
          return value if value.is_a?(String)

          raise Ibex::Error, "#{token.location}: expected text token"
        end
      end
    end
  end
end
