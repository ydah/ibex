# frozen_string_literal: true

module Ibex
  module Frontend
    # Parses productions and extended RHS items.
    module BootstrapParserRules
      EXTENDED_SUFFIXES = {
        "?": AST::Optional, "*": AST::Star, "+": AST::Plus
      }.freeze #: Hash[Symbol, singleton(AST::Optional) | singleton(AST::Star) | singleton(AST::Plus)]

      private

      # @rbs () -> Array[AST::Rule]
      def parse_rules
        # @type self: BootstrapParser
        rules = [] #: Array[AST::Rule]
        rules << parse_rule until keyword?("end") || current.type == :eof
        fail_expected("at least one rule") if rules.empty?
        rules
      end

      # @rbs () -> AST::Rule
      def parse_rule
        # @type self: BootstrapParser
        lhs = expect(:identifier)
        expect(:":")
        alternatives = [] #: Array[AST::Alternative]
        loop do
          alternatives << parse_alternative(lhs)
          next if accept(:|)

          accept(:";")
          break
        end
        AST::Rule.new(lhs: token_string(lhs), alternatives: alternatives, loc: lhs.location)
      end

      # @rbs (Token lhs) -> AST::Alternative
      def parse_alternative(lhs)
        # @type self: BootstrapParser
        location = current.location
        items = [] #: Array[AST::item]
        precedence = nil #: String?
        until alternative_end?(lhs)
          if accept(:"=")
            precedence = parse_symbol_name
            break
          end
          items << parse_item
        end
        action = nil #: AST::InlineAction?
        last_item = items.last
        if last_item.is_a?(AST::InlineAction)
          items.pop
          action = last_item
        end
        AST::Alternative.new(items: items, action: action, precedence: precedence, loc: location)
      end

      # @rbs () -> AST::item
      def parse_item
        # @type self: BootstrapParser
        return parse_action if current.type == :action
        return parse_separated_list if separated_list?
        return parse_group if current.type == :"("

        token = expect_symbol
        named_reference = parse_named_reference
        item = AST::SymbolReference.new(name: token_string(token), named_reference: named_reference,
                                        loc: token.location)
        parse_suffix(item)
      end

      # @rbs () -> AST::InlineAction
      def parse_action
        # @type self: BootstrapParser
        token = advance
        AST::InlineAction.new(code: token_string(token), loc: token.location)
      end

      # @rbs () -> String?
      def parse_named_reference
        # @type self: BootstrapParser
        return nil unless current.type == :":"

        extended_only!(current.location, "named references")
        advance
        token_string(expect(:identifier))
      end

      # @rbs (AST::item item) -> AST::item
      def parse_suffix(item)
        # @type self: BootstrapParser
        while (wrapper = EXTENDED_SUFFIXES[current.type])
          extended_only!(current.location, "EBNF suffixes")
          item = wrapper.new(item: item, loc: advance.location)
        end
        item
      end

      # @rbs () -> AST::item
      def parse_group
        # @type self: BootstrapParser
        opening = advance
        extended_only!(opening.location, "EBNF groups")
        alternatives = [[]] #: Array[Array[AST::item]]
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

      # @rbs () -> AST::SeparatedList
      def parse_separated_list
        # @type self: BootstrapParser
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

      # @rbs (Token lhs) -> bool
      def alternative_end?(lhs)
        # @type self: BootstrapParser
        %i[| ; eof].include?(current.type) || keyword?("end") || rule_start?(lhs)
      end

      # @rbs (Token lhs) -> bool
      def rule_start?(lhs)
        # @type self: BootstrapParser
        current.type == :identifier && lookahead.type == :":" && current.location.column <= lhs.location.column
      end

      # @rbs () -> bool
      def separated_list?
        # @type self: BootstrapParser
        %w[separated_list separated_nonempty_list].include?(current.value) && lookahead.type == :"("
      end
    end
  end
end
