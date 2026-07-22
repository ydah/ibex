# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Classifies context-dependent tokens in the grammar rule section.
      class RuleState
        SCALAR_TYPES = { literal: :LITERAL, integer: :INTEGER, action: :ACTION, user_code: :USER_CODE }.freeze

        attr_reader :section, :state

        def initialize
          @state = :rules_lhs
          @section = :rules
          @delimiters = DelimiterTracker.new
        end

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

        def group_opening
          @delimiters.group_opening
        end

        def open_delimiter_kind
          @delimiters.open_kind
        end

        private

        def classify_identifier(token, remaining, last_external, previous_external)
          return rule_lhs(token) if @state == :rules_lhs
          return :IDENTIFIER unless @state == :rule_rhs
          return :IDENTIFIER if named_reference_name?(last_external, previous_external)
          return start_rule(token) if rule_boundary?(token, remaining.first)
          return finish_rules if token.value == "end"
          return separated_terminal(token) if separated_list_call?(token, remaining.first)

          :IDENTIFIER
        end

        def rule_lhs(token)
          if token.value == "end"
            @section = :user_code
            return :END
          end

          @lhs_column = token.location.column
          @state = :rule_colon
          :LHS
        end

        def named_reference_name?(last_external, previous_external)
          last_external == ":" && %i[IDENTIFIER LITERAL].include?(previous_external)
        end

        def rule_boundary?(token, following)
          following.type == :":" && token.location.column <= @lhs_column
        end

        def start_rule(token)
          @lhs_column = token.location.column
          @state = :rule_colon
          :LHS
        end

        def finish_rules
          @section = :user_code
          :END
        end

        def separated_list_call?(token, following)
          %w[separated_list separated_nonempty_list].include?(token.value) && following.type == :"("
        end

        def separated_terminal(token)
          token.value == "separated_list" ? :SEPARATED_LIST : :SEPARATED_NONEMPTY_LIST
        end

        def classify_punctuation(token)
          @state = :rule_rhs if @state == :rule_colon && token.type == :":"
          reset_rule_boundary if @state == :rule_rhs && token.type == :";" && @delimiters.empty?
          token.value
        end

        def reset_rule_boundary
          @lhs_column = nil
          @state = :rules_lhs
        end
      end
    end
  end
end
