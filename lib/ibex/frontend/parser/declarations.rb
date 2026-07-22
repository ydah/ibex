# frozen_string_literal: true

module Ibex
  module Frontend
    # Parses the declaration section of a grammar.
    module BootstrapParserDeclarations
      DECLARATIONS = %w[token prechigh preclow options expect start convert rule].freeze
      ASSOCIATIVITIES = %w[left right nonassoc].freeze

      private

      def parse_declarations
        # @type self: BootstrapParser
        declarations = [] #: Array[untyped]
        declarations << parse_declaration until keyword?("rule") || current.type == :eof
        declarations
      end

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

      def parse_tokens
        # @type self: BootstrapParser
        location = advance.location
        names = [] #: Array[untyped]
        names << parse_symbol_name until declaration_start?
        AST::Tokens.new(names: names, loc: location)
      end

      def parse_precedence
        # @type self: BootstrapParser
        opening = advance
        closing = opening.value == "prechigh" ? "preclow" : "prechigh"
        levels = precedence_levels(closing)
        expect_keyword(closing)
        AST::Precedence.new(direction: opening.value == "prechigh" ? :high_to_low : :low_to_high,
                            levels: levels, loc: opening.location)
      end

      def precedence_levels(closing)
        # @type self: BootstrapParser
        levels = [] #: Array[untyped]
        until keyword?(closing) || current.type == :eof
          association = expect_one_of(ASSOCIATIVITIES)
          symbols = [] #: Array[untyped]
          symbols << parse_symbol_name until association_start? || keyword?(closing) || current.type == :eof
          fail_at(association.location, "expected at least one precedence symbol") if symbols.empty?
          levels << AST::PrecedenceLevel.new(associativity: association.value.to_sym, symbols: symbols,
                                             loc: association.location)
        end
        levels
      end

      def parse_options
        # @type self: BootstrapParser
        location = advance.location
        names = [] #: Array[untyped]
        names << expect(:identifier).value until declaration_start?
        AST::Options.new(names: names, loc: location)
      end

      def parse_expect
        # @type self: BootstrapParser
        location = advance.location
        AST::Expect.new(conflicts: expect(:integer).value, loc: location)
      end

      def parse_start
        # @type self: BootstrapParser
        location = advance.location
        AST::Start.new(name: parse_symbol_name, loc: location)
      end

      def parse_convert
        # @type self: BootstrapParser
        location = advance.location
        pairs = [] #: Array[untyped]
        until keyword?("end") || current.type == :eof
          name_token = current
          name = parse_symbol_name
          expression = decode_conversion(tokens_on_line(name_token.location.line), name_token.location)
          pairs << AST::Conversion.new(name: name, expression: expression, loc: name_token.location)
        end
        expect_keyword("end")
        AST::Convert.new(pairs: pairs, loc: location)
      end

      def tokens_on_line(line)
        # @type self: BootstrapParser
        tokens = [] #: Array[untyped]
        tokens << advance while current.type != :eof && current.location.line == line && !keyword?("end")
        tokens
      end

      def decode_conversion(tokens, location)
        # @type self: BootstrapParser
        unless tokens.length == 1 && tokens.first.type == :literal
          fail_at(location, "expected a quoted Ruby conversion expression")
        end

        literal = tokens.first.value
        return literal.undump if literal.start_with?('"')

        literal[1...-1].gsub("\\'", "'").gsub("\\\\", "\\")
      rescue RuntimeError => e
        fail_at(location, "invalid conversion expression: #{e.message}")
      end

      def declaration_start?
        # @type self: BootstrapParser
        current.type == :eof || (current.type == :identifier && DECLARATIONS.include?(current.value))
      end

      def association_start?
        # @type self: BootstrapParser
        current.type == :identifier && ASSOCIATIVITIES.include?(current.value)
      end
    end
  end
end
