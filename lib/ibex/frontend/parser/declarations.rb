# frozen_string_literal: true

module Ibex
  module Frontend
    # Parses the declaration section of a grammar.
    module ParserDeclarations
      DECLARATIONS = %w[token prechigh preclow options expect start convert rule].freeze
      ASSOCIATIVITIES = %w[left right nonassoc].freeze

      private

      def parse_declarations
        declarations = []
        declarations << parse_declaration until keyword?("rule") || current.type == :eof
        declarations
      end

      def parse_declaration
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

      def parse_tokens
        location = advance.location
        names = []
        names << parse_symbol_name until declaration_start?
        AST::Tokens.new(names: names, loc: location)
      end

      def parse_precedence
        opening = advance
        closing = opening.value == "prechigh" ? "preclow" : "prechigh"
        levels = precedence_levels(closing)
        expect_keyword(closing)
        AST::Precedence.new(direction: opening.value == "prechigh" ? :high_to_low : :low_to_high,
                            levels: levels, loc: opening.location)
      end

      def precedence_levels(closing)
        levels = []
        until keyword?(closing) || current.type == :eof
          association = expect_one_of(ASSOCIATIVITIES)
          symbols = []
          symbols << parse_symbol_name until association_start? || keyword?(closing) || current.type == :eof
          fail_at(association.location, "expected at least one precedence symbol") if symbols.empty?
          levels << AST::PrecedenceLevel.new(associativity: association.value.to_sym, symbols: symbols,
                                             loc: association.location)
        end
        levels
      end

      def parse_options
        location = advance.location
        names = []
        names << expect(:identifier).value until declaration_start?
        AST::Options.new(names: names, loc: location)
      end

      def parse_expect
        location = advance.location
        AST::Expect.new(conflicts: expect(:integer).value, loc: location)
      end

      def parse_start
        location = advance.location
        AST::Start.new(name: parse_symbol_name, loc: location)
      end

      def parse_convert
        location = advance.location
        pairs = []
        until keyword?("end") || current.type == :eof
          name_token = current
          name = parse_symbol_name
          expression = tokens_on_line(name_token.location.line).map(&:value).join
          fail_at(name_token.location, "expected a conversion expression") if expression.empty?
          pairs << AST::Conversion.new(name: name, expression: expression, loc: name_token.location)
        end
        expect_keyword("end")
        AST::Convert.new(pairs: pairs, loc: location)
      end

      def tokens_on_line(line)
        tokens = []
        tokens << advance while current.type != :eof && current.location.line == line && !keyword?("end")
        tokens
      end

      def declaration_start?
        current.type == :eof || (current.type == :identifier && DECLARATIONS.include?(current.value))
      end

      def association_start?
        current.type == :identifier && ASSOCIATIVITIES.include?(current.value)
      end
    end
  end
end
