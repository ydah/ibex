# frozen_string_literal: true

module Ibex
  module Frontend
    # Parameter-list and parameterized-reference builders for the generated frontend.
    module GeneratedParserParameters
      private

      # @rbs (Token opening, Array[Token] parameters) -> [Token, Array[String]]
      def build_rule_parameters(opening, parameters)
        # @type self: GeneratedParserBase
        extended_only!(opening.location, "parameterized rules")
        [opening, parameters.map { |parameter| token_string(parameter) }]
      end

      # @rbs (Token callee, Token opening, Array[AST::item] arguments,
      #   [Token, Token]? named_reference, Array[Token] suffixes) -> AST::item
      def build_parameterized_reference(callee, opening, arguments, named_reference, suffixes)
        # @type self: GeneratedParserBase
        extended_only!(opening.location, "parameterized rules")
        require_adjacency!(callee, opening, "parameter list must immediately follow rule name")
        item = AST::ParameterizedReference.new(
          name: token_string(callee), arguments: arguments, named_reference: named_reference_value(named_reference),
          loc: callee.location
        )
        apply_suffixes(item, suffixes)
      end

      # @rbs (Token left, Token right, String message) -> void
      def require_adjacency!(left, right, message)
        # @type self: GeneratedParserBase
        left_span = left.span
        right_span = right.span
        adjacent = if left_span && right_span
                     left_span.end_byte == right_span.start_byte
                   else
                     left.location.line == right.location.line &&
                       left.location.column + token_string(left).length == right.location.column
                   end
        fail_at(right.location, message) unless adjacent
      end
    end
  end
end
