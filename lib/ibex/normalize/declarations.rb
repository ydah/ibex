# frozen_string_literal: true

module Ibex
  # Declaration extraction used by Normalizer.
  module NormalizeDeclarations
    private

    # @rbs () -> void
    def read_declarations
      # @type self: Normalizer
      @declared_tokens = {} #: Hash[String, IR::location]
      @precedence = {} #: Hash[String, IR::precedence]
      @precedence_locations = {} #: Hash[String, IR::location]
      @display_names = {} #: Hash[String, String]
      @display_name_locations = {} #: Hash[String, IR::location]
      @semantic_types = {} #: Hash[String, String]
      @semantic_type_locations = {} #: Hash[String, IR::location]
      @options = { result_var: true, omit_action_call: true }
      @options[:cst] = true if @ast.cst
      @expected_conflicts = 0
      @expected_rr_conflicts = nil
      @conversions = {} #: Hash[String, String]
      @parser_parameters = [] #: Array[IR::parser_parameter]
      @value_printers = {} #: Hash[String, IR::value_printer]
      @recovery_sync_tokens = [] #: Array[String]
      @recovery_sync_location = nil #: Frontend::Location?
      @on_error_reduce_groups = [] #: Array[Array[String]]
      @on_error_reduce_locations = {} #: Hash[String, Frontend::Location]
      @grammar_tests = [] #: Array[IR::grammar_test]
      @lexer_declaration = nil #: Frontend::AST::Lexer?
      @node_shapes = {} #: Hash[String, Array[String]]
      @ast.declarations.each { |declaration| read_declaration(declaration) }
    end

    # @rbs (Frontend::AST::declaration declaration) -> void
    def read_declaration(declaration) # rubocop:disable Metrics/CyclomaticComplexity
      # @type self: Normalizer
      case declaration
      when Frontend::AST::Tokens then read_tokens(declaration)
      when Frontend::AST::Precedence then read_precedence(declaration)
      when Frontend::AST::Options then read_options(declaration)
      when Frontend::AST::Expect then @expected_conflicts = declaration.conflicts
      when Frontend::AST::ExpectRR then @expected_rr_conflicts = declaration.conflicts
      when Frontend::AST::Start, Frontend::AST::Recovery, Frontend::AST::OnErrorReduce, Frontend::AST::GrammarTest
        read_parser_control_declaration(declaration)
      when Frontend::AST::Lexer
        fail_at(declaration.loc, "duplicate lexer declaration") if @lexer_declaration
        @lexer_declaration = declaration
      when Frontend::AST::Convert then read_conversions(declaration)
      when Frontend::AST::DisplayName, Frontend::AST::SemanticType, Frontend::AST::Parameter, Frontend::AST::Printer
        read_extended_declaration(declaration)
      when Frontend::AST::Include then fail_at(declaration.loc, "includes must be resolved before normalization")
      end
    end

    # @rbs (Frontend::AST::Start declaration) -> void
    def read_start_declaration(declaration)
      # @type self: Normalizer
      fail_at(declaration.loc, "duplicate start declaration") if @explicit_starts
      if declaration.names.length > 1 && @mode != :extended
        fail_at(declaration.loc, "multiple start symbols require extended mode")
      end
      fail_at(declaration.loc, "start declaration requires at least one symbol") if declaration.names.empty?
      unless declaration.names.uniq.length == declaration.names.length
        fail_at(declaration.loc, "start symbols must be unique")
      end

      @explicit_starts = declaration.names
      @start_location = declaration.loc
    end

    # @rbs (Frontend::AST::symbol_metadata | Frontend::AST::Parameter | Frontend::AST::Printer declaration) -> void
    def read_extended_declaration(declaration)
      if declaration.is_a?(Frontend::AST::Parameter)
        read_parser_parameter(declaration)
      elsif declaration.is_a?(Frontend::AST::Printer)
        read_value_printer(declaration)
      else
        read_symbol_metadata_declaration(declaration)
      end
    end

    # @rbs (Frontend::AST::Printer declaration) -> void
    def read_value_printer(declaration)
      # @type self: Normalizer
      if @value_printers.key?(declaration.name)
        fail_at(declaration.loc, "duplicate %printer declaration for #{declaration.name}")
      end

      @value_printers[declaration.name] = {
        symbol: declaration.name, code: declaration.code, loc: declaration.loc.to_h
      }
    end

    # @rbs () -> void
    def validate_value_printers
      @value_printers.each_value do |printer|
        next if @symbols_by_name.key?(printer[:symbol])

        location = printer[:loc]
        raise Ibex::Error,
              "#{location[:file]}:#{location[:line]}:#{location[:column]}: " \
              "%printer references missing symbol #{printer[:symbol]}"
      end
    end

    # @rbs (Frontend::AST::Parameter declaration) -> void
    def read_parser_parameter(declaration)
      # @type self: Normalizer
      if @parser_parameters.any? { |parameter| parameter[:name] == declaration.name }
        fail_at(declaration.loc, "duplicate %param declaration for #{declaration.name}")
      end
      unless declaration.name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)
        fail_at(declaration.loc, "%param name #{declaration.name.inspect} must be a Ruby local identifier")
      end
      if Normalizer::RUBY_KEYWORDS.include?(declaration.name)
        fail_at(declaration.loc, "%param name #{declaration.name.inspect} is a Ruby keyword")
      end

      @parser_parameters << { name: declaration.name, semantic_type: declaration.semantic_type }
    end

    # @rbs (Frontend::AST::Tokens declaration) -> void
    def read_tokens(declaration)
      # @type self: Normalizer
      declaration.names.each { |name| @declared_tokens[name] = declaration.loc.to_h }
      (declaration.aliases || {}).each do |name, value|
        fail_at(declaration.loc, "duplicate display declaration for #{name}") if @display_names.key?(name)

        @display_names[name] = value
        @display_name_locations[name] = declaration.loc.to_h
      end
    end

    # @rbs (Frontend::AST::Options declaration) -> void
    def read_options(declaration)
      declaration.names.each { |name| read_option(name, declaration.loc) }
    end

    # @rbs (Frontend::AST::Convert declaration) -> void
    def read_conversions(declaration)
      # @type self: Normalizer
      declaration.pairs.each { |pair| @conversions[pair.name] = pair.expression }
    end

    # @rbs (Frontend::AST::symbol_metadata declaration) -> void
    def read_symbol_metadata_declaration(declaration)
      # @type self: Normalizer
      if declaration.is_a?(Frontend::AST::DisplayName)
        read_symbol_metadata(declaration, @display_names, @display_name_locations, "display")
      else
        read_symbol_metadata(declaration, @semantic_types, @semantic_type_locations, "type")
      end
    end

    # @rbs (Frontend::AST::symbol_metadata declaration, Hash[String, String] values,
    #   Hash[String, IR::location] locations, String label) -> void
    def read_symbol_metadata(declaration, values, locations, label)
      # @type self: Normalizer
      if values.key?(declaration.name)
        fail_at(declaration.loc, "duplicate #{label} declaration for #{declaration.name}")
      end

      values[declaration.name] = declaration.value
      locations[declaration.name] = declaration.loc.to_h
    end

    # @rbs (Frontend::AST::Precedence declaration) -> void
    def read_precedence(declaration)
      # @type self: Normalizer
      count = declaration.levels.length
      declaration.levels.each_with_index do |level, index|
        numeric_level = declaration.direction == :high_to_low ? count - index : index + 1
        level.symbols.each do |name|
          @precedence[name] = { associativity: level.associativity, level: numeric_level }
          @precedence_locations[name] = level.loc.to_h
        end
      end
    end

    # @rbs (String name, Frontend::Location location) -> void
    def read_option(name, location)
      # @type self: Normalizer
      case name
      when "no_result_var" then @options[:result_var] = false
      when "result_var" then @options[:result_var] = true
      when "omit_action_call" then @options[:omit_action_call] = true
      when "no_omit_action_call" then @options[:omit_action_call] = false
      else fail_at(location, "unknown option #{name}")
      end
    end
  end
end
