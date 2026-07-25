# frozen_string_literal: true

module Ibex
  module Frontend
    class TokenAdapter
      # Root/fragment header and include-path transitions for declaration classification.
      module DeclarationDocumentState
        private

        # @rbs (Token token) -> external_token
        def class_keyword(token)
          # @type self: DeclarationState
          value = string_value(token)
          if value == "fragment"
            raise Ibex::Error, "#{token.location}: fragments require extended mode" unless @extended_mode

            @fragment = true
            @state = :declaration
            return :FRAGMENT
          end
          return :IDENTIFIER unless value == "class"

          @state = :class_name
          :CLASS
        end

        # @rbs (external_token type) -> external_token?
        def classify_include(type)
          # @type self: DeclarationState
          return unless @state == :include_path && type == :LITERAL

          @state = :declaration
          @declaration = nil
          type
        end

        # @rbs (Token token, String value) -> void
        def reject_fragment_pragma(token, value)
          # @type self: DeclarationState
          return unless @fragment && value == "pragma"

          raise Ibex::Error, "#{token.location}: pragma declarations are not allowed in fragments"
        end
      end
    end
  end
end
