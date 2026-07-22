# frozen_string_literal: true

module Ibex
  module Frontend
    # Parses productions and extended RHS items.
    module ParserRules
      EXTENDED_SUFFIXES = { "?": AST::Optional, "*": AST::Star, "+": AST::Plus }.freeze

      private

      def parse_rules
        rules = []
        rules << parse_rule until keyword?("end") || current.type == :eof
        fail_expected("at least one rule") if rules.empty?
        rules
      end

      def parse_rule
        lhs = expect(:identifier)
        expect(:":")
        alternatives = []
        loop do
          alternatives << parse_alternative(lhs)
          next if accept(:|)

          accept(:";")
          break
        end
        AST::Rule.new(lhs: lhs.value, alternatives: alternatives, loc: lhs.location)
      end

      def parse_alternative(lhs)
        location = current.location
        items = []
        precedence = nil
        until alternative_end?(lhs)
          if accept(:"=")
            precedence = parse_symbol_name
            break
          end
          items << parse_item
        end
        action = items.pop if items.last.is_a?(AST::InlineAction)
        AST::Alternative.new(items: items, action: action, precedence: precedence, loc: location)
      end

      def parse_item
        return parse_action if current.type == :action
        return parse_separated_list if separated_list?
        return parse_group if current.type == :"("

        token = expect_symbol
        named_reference = parse_named_reference
        item = AST::SymbolReference.new(name: token.value, named_reference: named_reference, loc: token.location)
        parse_suffix(item)
      end

      def parse_action
        token = advance
        AST::InlineAction.new(code: token.value, loc: token.location)
      end

      def parse_named_reference
        return nil unless current.type == :":"

        extended_only!(current.location, "named references")
        advance
        expect(:identifier).value
      end

      def parse_suffix(item)
        while (wrapper = EXTENDED_SUFFIXES[current.type])
          extended_only!(current.location, "EBNF suffixes")
          item = wrapper.new(item: item, loc: advance.location)
        end
        item
      end

      def parse_group
        opening = advance
        extended_only!(opening.location, "EBNF groups")
        alternatives = [[]]
        until current.type == :")"
          fail_at(opening.location, "unterminated EBNF group") if current.type == :eof || keyword?("end")
          if accept(:|)
            alternatives << []
            next
          end
          fail_at(current.location, "actions inside EBNF groups are not supported") if current.type == :action

          alternatives.last << parse_item
        end
        expect(:")")
        parse_suffix(AST::Group.new(alternatives: alternatives, loc: opening.location))
      end

      def parse_separated_list
        function = advance
        extended_only!(function.location, "separated lists")
        expect(:"(")
        item = parse_item
        expect(:",")
        separator = parse_item
        expect(:")")
        AST::SeparatedList.new(item: item, separator: separator,
                               nonempty: function.value == "separated_nonempty_list", loc: function.location)
      end

      def alternative_end?(lhs)
        %i[| ; eof].include?(current.type) || keyword?("end") || rule_start?(lhs)
      end

      def rule_start?(lhs)
        current.type == :identifier && lookahead.type == :":" && current.location.column <= lhs.location.column
      end

      def separated_list?
        %w[separated_list separated_nonempty_list].include?(current.value) && lookahead.type == :"("
      end
    end
  end
end
