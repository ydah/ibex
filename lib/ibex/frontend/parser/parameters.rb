# frozen_string_literal: true

module Ibex
  module Frontend
    # Parses extended-mode parameter lists and parameterized references during bootstrap.
    module BootstrapParserParameters
      private

      # @rbs (Token lhs) -> Array[String]
      def parse_rule_parameters(lhs)
        # @type self: BootstrapParser
        return [] unless current.type == :"(" && adjacent_tokens?(lhs, current)

        opening = advance
        extended_only!(opening.location, "parameterized rules")
        parameters = [token_string(expect(:identifier))]
        parameters << token_string(expect(:identifier)) while accept(:",")
        expect(:")")
        parameters
      end

      # @rbs () -> AST::item
      def parse_parameterized_reference
        # @type self: BootstrapParser
        callee = advance
        opening = expect(:"(")
        extended_only!(opening.location, "parameterized rules")
        arguments = [] #: Array[AST::item]
        unless current.type == :")"
          loop do
            fail_at(current.location, "actions are not valid parameter arguments") if current.type == :action

            arguments << parse_item
            break unless accept(:",")
          end
        end
        expect(:")")
        item = AST::ParameterizedReference.new(
          name: token_string(callee), arguments: arguments, named_reference: parse_named_reference, loc: callee.location
        )
        parse_suffix(item)
      end

      # @rbs () -> bool
      def parameterized_call?
        # @type self: BootstrapParser
        current.type == :identifier && lookahead.type == :"(" && adjacent_tokens?(current, lookahead)
      end

      # @rbs () -> bool
      def parameterized_rule_start?
        # @type self: BootstrapParser
        opening = lookahead
        return false unless opening.type == :"(" && adjacent_tokens?(current, opening)

        parameter_definition_tail?(@tokens.drop(@index + 2))
      end

      # @rbs (Array[Token] tail) -> bool
      def parameter_definition_tail?(tail)
        # @type self: BootstrapParser
        closing = tail.index { |token| token.type == :")" }
        return false unless closing && tail[closing + 1]&.type == :":"

        formals = tail.take(closing)
        !formals.empty? && formals.length.odd? &&
          formals.each_with_index.all? { |token, index| token.type == (index.even? ? :identifier : :",") }
      end

      # @rbs (Token left, Token right) -> bool
      def adjacent_tokens?(left, right)
        # @type self: BootstrapParser
        left_span = left.span
        right_span = right.span
        return left_span.end_byte == right_span.start_byte if left_span && right_span

        left.location.line == right.location.line &&
          left.location.column + token_string(left).length == right.location.column
      end
    end
  end
end
