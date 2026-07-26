# frozen_string_literal: true

require_relative "generated_parser_metadata"
require_relative "generated_parser_includes"
require_relative "generated_parser_parameters"

module Ibex
  module Frontend
    # Semantic support and token delivery for the generated grammar parser.
    # rubocop:disable Metrics/ClassLength -- generated grammar semantics share one parser support surface.
    class GeneratedParserBase < Runtime::Parser
      include GeneratedParserMetadata
      include GeneratedParserIncludes
      include GeneratedParserParameters

      attr_reader :diagnostic_token #: Token?

      # @rbs @adapter: TokenAdapter
      # @rbs @mode: Symbol

      # @rbs (Array[Token] tokens, ?mode: Symbol) -> void
      def initialize(tokens, mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        super()
        @adapter = TokenAdapter.new(tokens, extended: mode == :extended)
        @mode = mode
      end

      # @rbs () -> (AST::Root | AST::Fragment)
      def parse
        do_parse
      end

      # @rbs () -> ([external_token, Token] | false)
      def next_token
        delivered = @adapter.next_token
        @diagnostic_token = delivered ? delivered.fetch(1) : @adapter.eof_token
        delivered
      rescue Ibex::Error
        @diagnostic_token = @adapter.last_token || @adapter.eof_token
        raise
      end

      # @rbs (Integer? _token_id, Token? value, Array[untyped] _value_stack) -> bot
      def on_error(_token_id, value, _value_stack)
        token = value || @adapter.eof_token
        @diagnostic_token = token
        raise_contextual_error(token)

        received = token&.value || token&.type || :eof
        location = token&.location || Location.new(file: "(grammar)", line: 1, column: 1)
        expected = expected_description(token)
        raise Ibex::Error, "#{location}: expected #{expected}, got #{received}"
      end

      private

      # @rbs (Token? token) -> void
      def raise_contextual_error(token)
        raise_group_contextual_error(token)
        raise_conversion_contextual_error
      end

      # @rbs (Token? token) -> void
      def raise_group_contextual_error(token)
        group_opening = @adapter.group_opening
        if group_opening && token && token.type == :action
          fail_at(token.location, "actions inside EBNF groups are not supported")
        end
        group_unterminated = @adapter.open_delimiter_kind == :group &&
                             (token.nil? || token.type == :eof || token.value == "end")
        fail_at(group_opening.location, "unterminated EBNF group") if group_unterminated && group_opening
      end

      # @rbs () -> void
      def raise_conversion_contextual_error
        conversion_name = @adapter.conversion_name
        return unless @adapter.declaration == :convert
        return unless conversion_name

        fail_at(conversion_name.location, "expected a quoted Ruby conversion expression")
      end

      # @rbs (Token? token) -> String
      def expected_description(token)
        expectation = @adapter.expectation(token)
        return expectation if expectation
        return ")" if %i[separated parameter].include?(@adapter.open_delimiter_kind)

        structural_expectation(token)
      end

      # @rbs (Token? token) -> String
      def structural_expectation(token)
        return "rule" if @adapter.section == :declarations
        return "at least one rule" if @adapter.section == :user_code && token&.value == "end"
        return "eof" if @adapter.section == :user_code
        return "end" if @adapter.section == :rules && @adapter.eof_token

        "grammar syntax"
      end

      # @rbs (Token class_token, Array[String] class_parts, Array[String]? superclass,
      #   Array[AST::declaration] declarations, Array[AST::Rule] rules, AST::user_code user_code) -> AST::Root
      def build_root(class_token, class_parts, superclass, declarations, rules, user_code)
        AST::Root.new(class_name: class_parts.join("::"), superclass: superclass&.join("::"),
                      declarations: declarations, rules: rules, user_code: user_code, loc: class_token.location,
                      extended: @mode == :extended || @adapter.extended_pragma?)
      end

      # @rbs (Token keyword, Array[[String, String?]] entries) -> AST::Tokens
      def build_tokens(keyword, entries)
        aliases = entries.filter_map { |name, value| [name, value] if value }.to_h
        AST::Tokens.new(names: entries.map(&:first), aliases: aliases.empty? ? nil : aliases, loc: keyword.location)
      end

      # @rbs (Token token) -> [String, nil]
      def build_token_entry(token)
        [token_string(token), nil]
      end

      # @rbs (Token name, Token value) -> [String, String]
      def build_token_alias(name, value)
        extended_only!(name.location, "token aliases")
        unless name.location.line == value.location.line
          fail_at(name.location, "token alias must be written on one line")
        end

        [token_string(name), decode_metadata_value(value, "token alias")]
      end

      # @rbs (Token keyword, Symbol direction, Array[AST::PrecedenceLevel] levels) -> AST::Precedence
      def build_precedence(keyword, direction, levels)
        AST::Precedence.new(direction: direction, levels: levels, loc: keyword.location)
      end

      # @rbs (Token association, Array[String] symbols) -> AST::PrecedenceLevel
      def build_precedence_level(association, symbols)
        fail_at(association.location, "expected at least one precedence symbol") if symbols.empty?
        extended_only!(association.location, "%precedence") if token_string(association) == "precedence"

        AST::PrecedenceLevel.new(associativity: token_string(association).to_sym, symbols: symbols,
                                 loc: association.location)
      end

      # @rbs (Token keyword, Array[String] names) -> AST::Options
      def build_options(keyword, names)
        AST::Options.new(names: names, loc: keyword.location)
      end

      # @rbs (Token keyword, Token integer) -> AST::Expect
      def build_expect(keyword, integer)
        AST::Expect.new(conflicts: token_integer(integer), loc: keyword.location)
      end

      # @rbs (Token keyword, Token integer) -> AST::ExpectRR
      def build_expect_rr(keyword, integer)
        extended_only!(keyword.location, "expect-rr declarations")
        AST::ExpectRR.new(conflicts: token_integer(integer), loc: keyword.location)
      end

      # @rbs (Token keyword, Token name, Token? type) -> AST::Parameter
      def build_parameter(keyword, name, type)
        extended_only!(keyword.location, "%param")
        if type && (keyword.location.line != name.location.line || name.location.line != type.location.line)
          fail_at(keyword.location, "%param declaration must be written on one line")
        end

        semantic_type = type && decode_metadata_value(type, "%param")
        AST::Parameter.new(name: token_string(name), semantic_type: semantic_type, loc: keyword.location)
      end

      # @rbs (Token keyword, Token symbol, Token action) -> AST::Printer
      def build_printer(keyword, symbol, action)
        extended_only!(keyword.location, "%printer")
        AST::Printer.new(name: token_string(symbol), code: token_string(action), loc: keyword.location)
      end

      # @rbs (Token keyword, String name) -> AST::Start
      def build_start(keyword, name)
        AST::Start.new(name: name, loc: keyword.location)
      end

      # @rbs (Token keyword, Array[AST::Conversion] pairs) -> AST::Convert
      def build_convert(keyword, pairs)
        AST::Convert.new(pairs: pairs, loc: keyword.location)
      end

      # @rbs (Token name_token, Token literal_token) -> AST::Conversion
      def build_conversion(name_token, literal_token)
        unless name_token.location.line == literal_token.location.line
          fail_at(name_token.location, "expected a quoted Ruby conversion expression")
        end

        literal = token_string(literal_token)
        expression = if literal.start_with?('"')
                       literal.undump
                     else
                       (literal[1...-1] || "").gsub("\\'", "'").gsub("\\\\", "\\")
                     end
        AST::Conversion.new(name: token_string(name_token), expression: expression, loc: name_token.location)
      rescue RuntimeError => e
        fail_at(name_token.location, "invalid conversion expression: #{e.message}")
      end

      # @rbs (Array[AST::item] items, Token? precedence) -> AST::Alternative
      def build_alternative(items, precedence)
        last_token = @adapter.last_token
        location = item_start_location(items.first) || precedence&.location || last_token&.location
        raise Ibex::Error, "missing alternative location" unless location

        action = nil #: AST::InlineAction?
        last_item = items.last
        if last_item.is_a?(AST::InlineAction)
          items.pop
          action = last_item
        end
        AST::Alternative.new(items: items, action: action,
                             precedence: precedence && token_string(precedence), loc: location)
      end

      # @rbs (Token token) -> AST::Empty
      def build_empty(token)
        extended_only!(token.location, "%empty")
        AST::Empty.new(loc: token.location)
      end

      # @rbs (AST::item? item) -> Location?
      def item_start_location(item)
        return unless item

        if item.is_a?(AST::Optional) || item.is_a?(AST::Star) || item.is_a?(AST::Plus)
          return item_start_location(item.item)
        end

        item.loc
      end

      # @rbs (Token token, [Token, Token]? named_reference, Array[Token] suffixes) -> AST::item
      def build_symbol_reference(token, named_reference, suffixes)
        item = AST::SymbolReference.new(
          name: token_string(token), named_reference: named_reference_value(named_reference), loc: token.location
        )
        apply_suffixes(item, suffixes)
      end

      # @rbs ([Token, Token]? named_reference) -> String?
      def named_reference_value(named_reference)
        return unless named_reference

        colon, name = named_reference
        extended_only!(colon.location, "named references")
        token_string(name)
      end

      # @rbs (Token token) -> AST::InlineAction
      def build_action(token)
        AST::InlineAction.new(code: token_string(token), loc: token.location)
      end

      # @rbs (Token opening, Array[Array[AST::item]] alternatives, Array[Token] suffixes) -> AST::item
      def build_group(opening, alternatives, suffixes)
        extended_only!(opening.location, "EBNF groups")
        apply_suffixes(AST::Group.new(alternatives: alternatives, loc: opening.location), suffixes)
      end

      # @rbs (Token function, AST::item item, AST::item separator) -> AST::SeparatedList
      def build_separated_list(function, item, separator)
        extended_only!(function.location, "separated lists")
        AST::SeparatedList.new(item: item, separator: separator,
                               nonempty: function.value == "separated_nonempty_list", loc: function.location)
      end

      # @rbs (AST::item item, Array[Token] suffixes) -> AST::item
      def apply_suffixes(item, suffixes)
        suffixes.reduce(item) do |wrapped, suffix|
          extended_only!(suffix.location, "EBNF suffixes")
          case token_string(suffix)
          when "?" then AST::Optional.new(item: wrapped, loc: suffix.location)
          when "*" then AST::Star.new(item: wrapped, loc: suffix.location)
          when "+" then AST::Plus.new(item: wrapped, loc: suffix.location)
          else raise Ibex::Error, "#{suffix.location}: unknown EBNF suffix #{suffix.value.inspect}"
          end
        end
      end

      # @rbs (AST::user_code blocks, Token token) -> AST::user_code
      def append_user_code(blocks, token)
        value = token_user_code(token)
        blocks[value[:name]] << AST::UserCode.new(name: value[:name], code: value[:code], loc: token.location)
        blocks
      end

      # @rbs () -> AST::user_code
      def empty_user_code
        Hash.new { |hash, key| hash[key] = [] } #: AST::user_code
      end

      # @rbs (Location location, String feature) -> void
      def extended_only!(location, feature)
        return if @mode == :extended || @adapter.extended_pragma?

        fail_at(location, "#{feature} require extended mode")
      end

      # @rbs (Location location, String message) -> bot
      def fail_at(location, message)
        raise Ibex::Error, "#{location}: #{message}"
      end

      # @rbs (Token token) -> String
      def token_string(token)
        value = token.value
        return value if value.is_a?(String)

        fail_at(token.location, "expected text token")
      end

      # @rbs (Token token) -> Integer
      def token_integer(token)
        value = token.value
        return value if value.is_a?(Integer)

        fail_at(token.location, "expected integer token")
      end

      # @rbs (Token token) -> user_code_token
      def token_user_code(token)
        value = token.value
        return value if value.is_a?(Hash)

        fail_at(token.location, "expected user-code token")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
