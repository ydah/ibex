# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Context transitions for the extended root-only lexer declaration.
      module DeclarationLexerState
        private

        # @rbs () -> bool
        def lexer_declaration_state?
          @declaration == :lexer
        end

        # @rbs (Token token) -> external_token
        def classify_lexer_identifier(token)
          case @state
          when :lexer_entries, :lexer_action_or_entry then begin_lexer_entry(token)
          when :lexer_state_name
            @state = :lexer_state_do
            :IDENTIFIER
          when :lexer_state_do
            value = string_value(token)
            raise Ibex::Error, "#{token.location}: expected do, got #{value}" unless value == "do"

            @lexer_state_depth = (@lexer_state_depth || 0) + 1
            @state = :lexer_entries
            :DO
          else
            :IDENTIFIER
          end
        end

        # @rbs (Token token) -> external_token
        def begin_lexer_entry(token)
          value = string_value(token)
          case value
          when "end" then finish_lexer_scope
          when "state"
            @state = :lexer_state_name
            :STATE
          when "skip"
            @state = :lexer_pattern
            :SKIP
          when "on"
            @state = :lexer_pattern
            :ON
          else
            @state = :lexer_pattern
            :IDENTIFIER
          end
        end

        # @rbs () -> external_token
        def finish_lexer_scope
          depth = @lexer_state_depth || 0
          if depth.positive?
            @lexer_state_depth = depth - 1
            @state = :lexer_entries
          else
            @state = :declaration
            @declaration = nil
          end
          :END
        end

        # @rbs (external_token type) -> external_token?
        def classify_lexer_scalar(type)
          if @state == :lexer_pattern && %i[REGEXP LITERAL].include?(type)
            @state = :lexer_action_or_entry
            return type
          end
          return unless @state == :lexer_action_or_entry && type == :ACTION

          @state = :lexer_entries
          type
        end
      end
    end
  end
end
