# frozen_string_literal: true

module Ibex
  # Declaration extraction used by Normalizer.
  module NormalizeDeclarations
    private

    def read_declarations
      @declared_tokens = {}
      @precedence = {}
      @precedence_locations = {}
      @options = { result_var: true, omit_action_call: true }
      @expected_conflicts = 0
      @conversions = {}
      @ast.declarations.each { |declaration| read_declaration(declaration) }
    end

    def read_declaration(declaration)
      case declaration
      when Frontend::AST::Tokens then declaration.names.each { |name| @declared_tokens[name] = declaration.loc.to_h }
      when Frontend::AST::Precedence then read_precedence(declaration)
      when Frontend::AST::Options then declaration.names.each { |name| read_option(name, declaration.loc) }
      when Frontend::AST::Expect then @expected_conflicts = declaration.conflicts
      when Frontend::AST::Start
        @explicit_start = declaration.name
        @start_location = declaration.loc
      when Frontend::AST::Convert then declaration.pairs.each { |pair| @conversions[pair.name] = pair.expression }
      end
    end

    def read_precedence(declaration)
      count = declaration.levels.length
      declaration.levels.each_with_index do |level, index|
        numeric_level = declaration.direction == :high_to_low ? count - index : index + 1
        level.symbols.each do |name|
          @precedence[name] = { associativity: level.associativity, level: numeric_level }
          @precedence_locations[name] = level.loc.to_h
        end
      end
    end

    def read_option(name, location)
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
