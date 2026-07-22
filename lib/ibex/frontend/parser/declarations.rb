# frozen_string_literal: true

module Ibex
  module Frontend
    # Parses the declaration section of a grammar.
    module BootstrapParserDeclarations
      DECLARATIONS = %w[token prechigh preclow options expect start convert rule].freeze #: Array[String]
      ASSOCIATIVITIES = %w[left right nonassoc].freeze #: Array[String]

      private

      # @rbs () -> Array[AST::declaration]
      def parse_declarations
        # @type self: BootstrapParser
        declarations = [] #: Array[AST::declaration]
        declarations << parse_declaration until keyword?("rule") || current.type == :eof
        declarations
      end

      # @rbs () -> AST::declaration
      def parse_declaration
        # @type self: BootstrapParser
        case current.value
        when "token" then parse_tokens
        when "prechigh", "preclow" then parse_precedence
        when "options" then parse_options
        when "expect" then parse_expect
        when "start" then parse_start
        when "convert" then parse_convert
        else fail_expected("a declaration or rule")
        end
      end

      # @rbs () -> AST::Tokens
      def parse_tokens
        # @type self: BootstrapParser
        location = advance.location
        names = [] #: Array[String]
        names << parse_symbol_name until declaration_start?
        AST::Tokens.new(names: names, loc: location)
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

      # @rbs () -> AST::Start
      def parse_start
        # @type self: BootstrapParser
        location = advance.location
        AST::Start.new(name: parse_symbol_name, loc: location)
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

      # @rbs () -> bool
      def declaration_start?
        # @type self: BootstrapParser
        current.type == :eof || (current.type == :identifier && DECLARATIONS.include?(current.value))
      end

      # @rbs () -> bool
      def association_start?
        # @type self: BootstrapParser
        current.type == :identifier && ASSOCIATIVITIES.include?(current.value)
      end
    end
  end
end
