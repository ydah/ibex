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
      @conversions = {} #: Hash[String, String]
      @ast.declarations.each { |declaration| read_declaration(declaration) }
    end

    # @rbs (Frontend::AST::declaration declaration) -> void
    def read_declaration(declaration)
      # @type self: Normalizer
      case declaration
      when Frontend::AST::Tokens then declaration.names.each { |name| @declared_tokens[name] = declaration.loc.to_h }
      when Frontend::AST::Precedence then read_precedence(declaration)
      when Frontend::AST::Options then declaration.names.each { |name| read_option(name, declaration.loc) }
      when Frontend::AST::Expect then @expected_conflicts = declaration.conflicts
      when Frontend::AST::Start
        @explicit_start = declaration.name
        @start_location = declaration.loc
      when Frontend::AST::Convert then declaration.pairs.each { |pair| @conversions[pair.name] = pair.expression }
      else read_symbol_metadata_declaration(declaration)
      end
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
