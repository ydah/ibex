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
      @expected_conflicts = 0
      @expected_rr_conflicts = nil
      @conversions = {} #: Hash[String, String]
      @parser_parameters = [] #: Array[IR::parser_parameter]
      @ast.declarations.each { |declaration| read_declaration(declaration) }
    end

    # @rbs (Frontend::AST::declaration declaration) -> void
    def read_declaration(declaration)
      # @type self: Normalizer
      case declaration
      when Frontend::AST::Tokens then read_tokens(declaration)
      when Frontend::AST::Precedence then read_precedence(declaration)
      when Frontend::AST::Options then read_options(declaration)
      when Frontend::AST::Expect then @expected_conflicts = declaration.conflicts
      when Frontend::AST::ExpectRR then @expected_rr_conflicts = declaration.conflicts
      when Frontend::AST::Start
        @explicit_start = declaration.name
        @start_location = declaration.loc
      when Frontend::AST::Convert then read_conversions(declaration)
      when Frontend::AST::DisplayName, Frontend::AST::SemanticType, Frontend::AST::Parameter
        read_extended_declaration(declaration)
      when Frontend::AST::Include then fail_at(declaration.loc, "includes must be resolved before normalization")
      end
    end

    # @rbs (Frontend::AST::symbol_metadata | Frontend::AST::Parameter declaration) -> void
    def read_extended_declaration(declaration)
      if declaration.is_a?(Frontend::AST::Parameter)
        read_parser_parameter(declaration)
      else
        read_symbol_metadata_declaration(declaration)
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
