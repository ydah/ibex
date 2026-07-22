# frozen_string_literal: true

module Ibex
  module Frontend
    # Semantic support and token delivery for the generated grammar parser.
    class GeneratedParserBase < Runtime::Parser
      def initialize(tokens, mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        super()
        @adapter = TokenAdapter.new(tokens)
        @mode = mode
      end

      def parse
        do_parse
      end

      def next_token
        @adapter.next_token
      end

      def on_error(_token_id, value, _value_stack)
        token = value || @adapter.eof_token
        raise_contextual_error(token)

        received = token&.value || token&.type || :eof
        location = token&.location || Location.new(file: "(grammar)", line: 1, column: 1)
        expected = expected_description(token)
        raise Ibex::Error, "#{location}: expected #{expected}, got #{received}"
      end

      private

      def raise_contextual_error(token)
        if @adapter.group_opening && token&.type == :action
          fail_at(token.location, "actions inside EBNF groups are not supported")
        end
        group_unterminated = @adapter.open_delimiter_kind == :group &&
                             (token.nil? || token.type == :eof || token.value == "end")
        fail_at(@adapter.group_opening.location, "unterminated EBNF group") if group_unterminated
        return unless @adapter.declaration == :convert && @adapter.conversion_name

        fail_at(@adapter.conversion_name.location, "expected a quoted Ruby conversion expression")
      end

      def expected_description(token)
        expectation = @adapter.expectation(token)
        return expectation if expectation
        return ")" if @adapter.open_delimiter_kind == :separated

        structural_expectation(token)
      end

      def structural_expectation(token)
        return "rule" if @adapter.section == :declarations
        return "at least one rule" if @adapter.section == :user_code && token&.value == "end"
        return "eof" if @adapter.section == :user_code
        return "end" if @adapter.section == :rules && @adapter.eof_token

        "grammar syntax"
      end

      def build_root(class_token, class_parts, superclass, declarations, rules, user_code)
        AST::Root.new(class_name: class_parts.join("::"), superclass: superclass&.join("::"),
                      declarations: declarations, rules: rules, user_code: user_code, loc: class_token.location)
      end

      def build_tokens(keyword, names)
        AST::Tokens.new(names: names, loc: keyword.location)
      end

      def build_precedence(keyword, direction, levels)
        AST::Precedence.new(direction: direction, levels: levels, loc: keyword.location)
      end

      def build_precedence_level(association, symbols)
        fail_at(association.location, "expected at least one precedence symbol") if symbols.empty?

        AST::PrecedenceLevel.new(associativity: association.value.to_sym, symbols: symbols,
                                 loc: association.location)
      end

      def build_options(keyword, names)
        AST::Options.new(names: names, loc: keyword.location)
      end

      def build_expect(keyword, integer)
        AST::Expect.new(conflicts: integer.value, loc: keyword.location)
      end

      def build_start(keyword, name)
        AST::Start.new(name: name, loc: keyword.location)
      end

      def build_convert(keyword, pairs)
        AST::Convert.new(pairs: pairs, loc: keyword.location)
      end

      def build_conversion(name_token, literal_token)
        unless name_token.location.line == literal_token.location.line
          fail_at(name_token.location, "expected a quoted Ruby conversion expression")
        end

        literal = literal_token.value
        expression = if literal.start_with?('"')
                       literal.undump
                     else
                       literal[1...-1].gsub("\\'", "'").gsub("\\\\", "\\")
                     end
        AST::Conversion.new(name: name_token.value, expression: expression, loc: name_token.location)
      rescue RuntimeError => e
        fail_at(name_token.location, "invalid conversion expression: #{e.message}")
      end

      def build_rule(lhs, alternatives)
        AST::Rule.new(lhs: lhs.value, alternatives: alternatives, loc: lhs.location)
      end

      def build_alternative(items, precedence)
        location = item_start_location(items.first) || precedence&.location || @adapter.last_token.location
        action = items.pop if items.last.is_a?(AST::InlineAction)
        AST::Alternative.new(items: items, action: action, precedence: precedence&.value, loc: location)
      end

      def item_start_location(item)
        return unless item

        wrapper = item.is_a?(AST::Optional) || item.is_a?(AST::Star) || item.is_a?(AST::Plus)
        return item_start_location(item.item) if wrapper

        item.loc
      end

      def build_symbol_reference(token, named_reference, suffixes)
        if named_reference
          colon, name = named_reference
          extended_only!(colon.location, "named references")
          named_reference = name.value
        end
        item = AST::SymbolReference.new(name: token.value, named_reference: named_reference, loc: token.location)
        apply_suffixes(item, suffixes)
      end

      def build_action(token)
        AST::InlineAction.new(code: token.value, loc: token.location)
      end

      def build_group(opening, alternatives, suffixes)
        extended_only!(opening.location, "EBNF groups")
        apply_suffixes(AST::Group.new(alternatives: alternatives, loc: opening.location), suffixes)
      end

      def build_separated_list(function, item, separator)
        extended_only!(function.location, "separated lists")
        AST::SeparatedList.new(item: item, separator: separator,
                               nonempty: function.value == "separated_nonempty_list", loc: function.location)
      end

      def apply_suffixes(item, suffixes)
        suffixes.reduce(item) do |wrapped, suffix|
          extended_only!(suffix.location, "EBNF suffixes")
          suffix_class = { "?" => AST::Optional, "*" => AST::Star, "+" => AST::Plus }.fetch(suffix.value)
          suffix_class.new(item: wrapped, loc: suffix.location)
        end
      end

      def append_user_code(blocks, token)
        value = token.value
        blocks[value[:name]] << AST::UserCode.new(name: value[:name], code: value[:code], loc: token.location)
        blocks
      end

      def empty_user_code
        Hash.new { |hash, key| hash[key] = [] }
      end

      def extended_only!(location, feature)
        return if @mode == :extended

        fail_at(location, "#{feature} require extended mode")
      end

      def fail_at(location, message)
        raise Ibex::Error, "#{location}: #{message}"
      end
    end
  end
end
