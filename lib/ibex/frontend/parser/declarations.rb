# frozen_string_literal: true

module Ibex
  module Frontend
    # Parses the declaration section of a grammar.
    # rubocop:disable Metrics/ModuleLength, Metrics/CyclomaticComplexity
    # Bootstrap declarations intentionally mirror the generated frontend's complete declaration vocabulary.
    module BootstrapParserDeclarations
      DECLARATIONS = %w[
        include import token prechigh preclow options expect expect_rr start recover on_error_reduce
        test lexer convert display type param printer parser pragma rule
      ].freeze #: Array[String]
      ASSOCIATIVITIES = %w[left right nonassoc precedence].freeze #: Array[String]

      private

      # @rbs () -> Array[AST::declaration]
      def parse_declarations
        # @type self: BootstrapParser
        declarations = [] #: Array[AST::declaration]
        declarations << parse_declaration until keyword?("rule") || current.type == :eof
        declarations
      end

      # @rbs () -> void
      def parse_pragmas
        # @type self: BootstrapParser
        while keyword?("pragma")
          keyword = current
          advance
          value = expect(:identifier)
          name = token_string(value)
          fail_at(value.location, "unknown pragma #{name}") unless %w[extended cst].include?(name)
          fail_at(keyword.location, "duplicate pragma #{name}") if @pragmas[name]

          @pragmas[name] = keyword.location
          @mode = :extended
        end
      end

      # @rbs () -> AST::declaration
      def parse_declaration
        # @type self: BootstrapParser
        case current.value
        when "include", "import" then parse_import
        when "token" then parse_tokens
        when "prechigh", "preclow" then parse_precedence
        when "options" then parse_options
        when "expect" then parse_expect
        when "expect_rr" then parse_expect_rr
        when "start" then parse_start
        when "recover" then parse_recovery
        when "on_error_reduce" then parse_on_error_reduce
        when "test" then parse_grammar_test
        when "lexer" then parse_lexer
        when "convert" then parse_convert
        when "display" then parse_symbol_metadata(AST::DisplayName, "display")
        when "type" then parse_symbol_metadata(AST::SemanticType, "type")
        when "param" then parse_parameter
        when "printer" then parse_printer
        when "parser" then parse_parser_configuration
        when "pragma" then fail_at(current.location, "expected rule, got pragma")
        else fail_expected("a declaration or rule")
        end
      end

      # @rbs () -> AST::ParserConfiguration
      def parse_parser_configuration
        # @type self: BootstrapParser
        keyword = advance
        settings = [] #: Array[AST::ParserSetting]
        until keyword?("end") || current.type == :eof
          key = expect(:identifier)
          value = expect(:identifier)
          settings << build_parser_setting(key, value)
        end
        expect_keyword("end")
        build_parser_configuration(keyword, settings)
      end

      # @rbs () -> AST::Include
      def parse_import
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "#{keyword.value}s")
        path = expect(:literal)
        value = token_string(path)
        unless value.start_with?('"') && value.end_with?('"')
          fail_at(path.location, "#{keyword.value} path must use a double-quoted string")
        end

        decoded = begin
          value.undump
        rescue RuntimeError => e
          fail_at(path.location, "invalid #{keyword.value} path: #{e.message}")
        end
        AST::Include.new(path: decoded, loc: keyword.location)
      end

      # @rbs () -> AST::Tokens
      def parse_tokens
        # @type self: BootstrapParser
        location = advance.location
        names = [] #: Array[String]
        aliases = {} #: Hash[String, String]
        until declaration_start?
          name_token = expect_symbol
          name = token_string(name_token)
          names << name
          next unless @mode == :extended && name_token.type == :identifier &&
                      current.type == :literal && current.location.line == name_token.location.line

          aliases[name] = decode_quoted_literal(advance, "token alias")
        end
        AST::Tokens.new(names: names, aliases: aliases.empty? ? nil : aliases, loc: location)
      end

      # @rbs () -> AST::Precedence
      def parse_precedence
        # @type self: BootstrapParser
        opening = advance
        opening_name = token_string(opening)
        closing = opening_name == "prechigh" ? "preclow" : "prechigh"
        levels = precedence_levels(closing)
        expect_keyword(closing)
        AST::Precedence.new(direction: opening_name == "prechigh" ? :high_to_low : :low_to_high,
                            levels: levels, loc: opening.location)
      end

      # @rbs (String closing) -> Array[AST::PrecedenceLevel]
      def precedence_levels(closing)
        # @type self: BootstrapParser
        levels = [] #: Array[AST::PrecedenceLevel]
        until keyword?(closing) || current.type == :eof
          association = expect_one_of(ASSOCIATIVITIES)
          extended_only!(association.location, "%precedence") if token_string(association) == "precedence"
          symbols = [] #: Array[String]
          symbols << parse_symbol_name until association_start? || keyword?(closing) || current.type == :eof
          fail_at(association.location, "expected at least one precedence symbol") if symbols.empty?
          levels << AST::PrecedenceLevel.new(associativity: token_string(association).to_sym, symbols: symbols,
                                             loc: association.location)
        end
        levels
      end

      # @rbs () -> AST::Options
      def parse_options
        # @type self: BootstrapParser
        location = advance.location
        names = [] #: Array[String]
        names << token_string(expect(:identifier)) until declaration_start?
        AST::Options.new(names: names, loc: location)
      end

      # @rbs () -> AST::Expect
      def parse_expect
        # @type self: BootstrapParser
        location = advance.location
        AST::Expect.new(conflicts: token_integer(expect(:integer)), loc: location)
      end

      # @rbs () -> AST::ExpectRR
      def parse_expect_rr
        # @type self: BootstrapParser
        location = advance.location
        extended_only!(location, "expect-rr declarations")
        AST::ExpectRR.new(conflicts: token_integer(expect(:integer)), loc: location)
      end

      # @rbs () -> AST::Parameter
      def parse_parameter
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "%param")
        name = expect(:identifier)
        type = current.type == :literal ? advance : nil
        if type && (keyword.location.line != name.location.line || name.location.line != type.location.line)
          fail_at(keyword.location, "%param declaration must be written on one line")
        end

        semantic_type = type && decode_quoted_literal(type, "%param")
        AST::Parameter.new(name: token_string(name), semantic_type: semantic_type, loc: keyword.location)
      end

      # @rbs () -> AST::Printer
      def parse_printer
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "%printer")
        name = parse_symbol_name
        action = expect(:action)
        AST::Printer.new(name: name, code: token_string(action), loc: keyword.location)
      end

      # @rbs () -> AST::Start
      def parse_start
        # @type self: BootstrapParser
        location = advance.location
        names = [parse_symbol_name]
        names << parse_symbol_name until declaration_start?
        extended_only!(location, "multiple start symbols") if names.length > 1
        AST::Start.new(names: names, loc: location)
      end

      # @rbs () -> AST::Recovery
      def parse_recovery
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "%recover")
        kind = expect(:identifier)
        fail_at(kind.location, "expected sync, got #{kind.value}") unless token_string(kind) == "sync"
        expect(:":")
        tokens = [parse_symbol_name]
        tokens << parse_symbol_name until declaration_start?
        AST::Recovery.new(sync_tokens: tokens, loc: keyword.location)
      end

      # @rbs () -> AST::OnErrorReduce
      def parse_on_error_reduce
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "%on_error_reduce")
        names = [parse_symbol_name]
        names << parse_symbol_name until declaration_start?
        AST::OnErrorReduce.new(names: names, loc: keyword.location)
      end

      # @rbs () -> AST::GrammarTest
      def parse_grammar_test
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "%test")
        expectation = token_string(expect(:identifier))
        fail_at(keyword.location, "expected accept or reject, got #{expectation}") unless
          %w[accept reject].include?(expectation)
        source = expect(:literal)
        literal = token_string(source)
        fail_at(source.location, "%test source must use a double-quoted string") unless literal.start_with?('"')
        decoded = begin
          literal.undump
        rescue RuntimeError => e
          fail_at(source.location, "invalid %test source: #{e.message}")
        end

        AST::GrammarTest.new(expectation: expectation.to_sym, source: decoded, loc: keyword.location)
      end

      # @rbs () -> AST::Lexer
      def parse_lexer
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "lexer declarations")
        entries = parse_lexer_entries
        expect_keyword("end")
        AST::Lexer.new(definitions: entries, loc: keyword.location)
      end

      # @rbs () -> Array[AST::lexer_entry]
      def parse_lexer_entries
        # @type self: BootstrapParser
        entries = [] #: Array[AST::lexer_entry]
        entries << parse_lexer_entry until keyword?("end") || current.type == :eof
        entries
      end

      # @rbs () -> AST::lexer_entry
      def parse_lexer_entry
        # @type self: BootstrapParser
        return parse_lexer_state if keyword?("state")

        marker = expect(:identifier)
        kind = case token_string(marker)
               when "skip" then :skip
               when "on" then :on
               else :token
               end
        pattern = expect_lexer_pattern
        action = current.type == :action ? advance : nil
        fail_at(marker.location, "on lexer rules require an action") if kind == :on && !action
        build_bootstrap_lexer_rule(kind, marker, pattern, action)
      end

      # @rbs () -> AST::LexerState
      def parse_lexer_state
        # @type self: BootstrapParser
        marker = advance
        name = expect(:identifier)
        expect_keyword("do")
        entries = parse_lexer_entries
        expect_keyword("end")
        AST::LexerState.new(name: token_string(name), definitions: entries, loc: marker.location)
      end

      # @rbs () -> Token
      def expect_lexer_pattern
        # @type self: BootstrapParser
        return advance if %i[regexp literal].include?(current.type)

        fail_expected("a regular expression or quoted literal")
      end

      # @rbs (Symbol kind, Token marker, Token pattern, Token? action) -> AST::LexerRule
      def build_bootstrap_lexer_rule(kind, marker, pattern, action)
        # @type self: BootstrapParser
        token = kind == :token ? token_string(marker) : nil
        AST::LexerRule.new(kind: kind, token: token, pattern: token_string(pattern),
                           pattern_kind: pattern.type, action: action && token_string(action), loc: marker.location)
      end

      # @rbs () -> AST::Convert
      def parse_convert
        # @type self: BootstrapParser
        location = advance.location
        pairs = [] #: Array[AST::Conversion]
        until keyword?("end") || current.type == :eof
          name_token = current
          name = parse_symbol_name
          expression = decode_conversion(tokens_on_line(name_token.location.line), name_token.location)
          pairs << AST::Conversion.new(name: name, expression: expression, loc: name_token.location)
        end
        expect_keyword("end")
        AST::Convert.new(pairs: pairs, loc: location)
      end

      # @rbs (singleton(AST::DisplayName) | singleton(AST::SemanticType) node_class, String feature) ->
      #   (AST::DisplayName | AST::SemanticType)
      def parse_symbol_metadata(node_class, feature)
        # @type self: BootstrapParser
        keyword = advance
        extended_only!(keyword.location, "#{feature} declarations")
        name = expect_symbol
        value = expect_metadata_value
        validate_metadata_line(keyword, name, value, feature)
        decoded = decode_quoted_literal(value, feature)
        node_class.new(name: token_string(name), value: decoded, loc: keyword.location)
      end

      # @rbs () -> Token
      def expect_metadata_value
        # @type self: BootstrapParser
        return advance if current.type == :literal

        fail_expected("a quoted string")
      end

      # @rbs (Integer line) -> Array[Token]
      def tokens_on_line(line)
        # @type self: BootstrapParser
        tokens = [] #: Array[Token]
        tokens << advance while current.type != :eof && current.location.line == line && !keyword?("end")
        tokens
      end

      # @rbs (Array[Token] tokens, Location location) -> String
      def decode_conversion(tokens, location)
        # @type self: BootstrapParser
        unless tokens.length == 1 && tokens.first.type == :literal
          fail_at(location, "expected a quoted Ruby conversion expression")
        end

        literal = token_string(tokens.first)
        return literal.undump if literal.start_with?('"')

        (literal[1...-1] || "").gsub("\\'", "'").gsub("\\\\", "\\")
      rescue RuntimeError => e
        fail_at(location, "invalid conversion expression: #{e.message}")
      end

      # @rbs (Token keyword, Token name, Token value, String feature) -> void
      def validate_metadata_line(keyword, name, value, feature)
        # @type self: BootstrapParser
        return if keyword.location.line == name.location.line && name.location.line == value.location.line

        fail_at(keyword.location, "#{feature} declaration must be written on one line")
      end

      # @rbs (Token token, String feature) -> String
      def decode_quoted_literal(token, feature)
        # @type self: BootstrapParser
        literal = token_string(token)
        decoded = if literal.start_with?('"')
                    literal.undump
                  else
                    (literal[1...-1] || "").gsub("\\'", "'").gsub("\\\\", "\\")
                  end
        fail_at(token.location, "#{feature} value must not be empty") if decoded.strip.empty?
        fail_at(token.location, "#{feature} value must be a single line") if decoded.match?(/[\r\n]/)
        fail_at(token.location, "#{feature} value must not contain control characters") if
          decoded.match?(/[[:cntrl:]]/)

        decoded
      rescue RuntimeError => e
        fail_at(token.location, "invalid #{feature} value: #{e.message}")
      end

      # @rbs () -> bool
      def declaration_start?
        # @type self: BootstrapParser
        return true if current.type == :eof
        return false unless current.type == :identifier && DECLARATIONS.include?(current.value)
        return false if %w[display type param printer lexer].include?(current.value) && @mode != :extended

        true
      end

      # @rbs () -> bool
      def association_start?
        # @type self: BootstrapParser
        current.type == :identifier && ASSOCIATIVITIES.include?(current.value)
      end
    end
    # rubocop:enable Metrics/ModuleLength, Metrics/CyclomaticComplexity
  end
end
