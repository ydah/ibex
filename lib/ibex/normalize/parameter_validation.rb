# frozen_string_literal: true

module Ibex
  # Static validation and collection of parameterized user rule definitions.
  module NormalizeParameterValidation
    private

    # @rbs () -> void
    def gather_parameter_templates
      # @type self: Normalizer
      @parameter_templates = {} #: Hash[String, Array[Frontend::AST::Rule]]
      @parameter_formals = {} #: Hash[String, Array[String]]
      plain_rules = {} #: Hash[String, Frontend::AST::Rule]
      @rule_documentation = validated_rule_documentation

      @ast.rules.each do |rule|
        if parameterized_rule?(rule)
          gather_parameterized_rule(rule, plain_rules)
        else
          reject_mixed_parameterized_rule(rule) if @parameter_templates.key?(rule.lhs)
          plain_rules[rule.lhs] ||= rule
        end
      end
      validate_parameter_terminal_collisions
      @ast.rules.each { |rule| validate_parameter_references(rule) }
    end

    # @rbs (Frontend::AST::Rule rule, Hash[String, Frontend::AST::Rule] plain_rules) -> void
    def gather_parameterized_rule(rule, plain_rules)
      # @type self: Normalizer
      reject_mixed_parameterized_rule(rule) if plain_rules.key?(rule.lhs)
      duplicate = rule.parameters.tally.find { |_name, count| count > 1 }&.first
      fail_at(rule.loc, "duplicate parameter #{duplicate} in rule #{rule.lhs}") if duplicate

      validate_parameter_formals(rule)
      @parameter_formals[rule.lhs] ||= rule.parameters
      (@parameter_templates[rule.lhs] ||= Array.new(0)) << rule
    end

    # @rbs (Frontend::AST::Rule rule) -> void
    def validate_parameter_formals(rule)
      # @type self: Normalizer
      expected = @parameter_formals[rule.lhs]
      return unless expected && expected != rule.parameters

      fail_at(
        rule.loc,
        "parameterized rule #{rule.lhs} uses inconsistent parameters " \
        "(expected #{expected.join(', ')}, got #{rule.parameters.join(', ')})"
      )
    end

    # @rbs (Frontend::AST::Rule rule) -> bot
    def reject_mixed_parameterized_rule(rule)
      # @type self: Normalizer
      fail_at(rule.loc, "rule #{rule.lhs} has both plain and parameterized definitions")
    end

    # @rbs () -> void
    def validate_parameter_terminal_collisions
      # @type self: Normalizer
      @parameter_templates.each do |name, rules|
        next unless @declared_tokens.key?(name) || @precedence.key?(name)

        fail_at(rules.fetch(0).loc, "parameterized rule #{name} collides with terminal #{name}")
      end
    end

    # @rbs (Frontend::AST::Rule rule) -> void
    def validate_parameter_references(rule)
      # @type self: Normalizer
      rule.alternatives.each do |alternative|
        alternative.items.each do |item|
          validate_parameter_item(item, rule.parameters, inside_argument: false)
        end
      end
    end

    # @rbs (Frontend::AST::item item, Array[String] formals, inside_argument: bool) -> void
    def validate_parameter_item(item, formals, inside_argument:)
      # @type self: Normalizer
      case item
      when Frontend::AST::ParameterizedReference
        validate_parameterized_item(item, formals, inside_argument: inside_argument)
      when Frontend::AST::SymbolReference
        reject_argument_named_reference(item) if inside_argument && item.named_reference
      when Frontend::AST::Group
        item.alternatives.flatten.each do |child|
          validate_parameter_item(child, formals, inside_argument: inside_argument)
        end
      when Frontend::AST::Optional, Frontend::AST::Star, Frontend::AST::Plus
        validate_parameter_item(item.item, formals, inside_argument: inside_argument)
      when Frontend::AST::SeparatedList
        validate_parameter_item(item.item, formals, inside_argument: inside_argument)
        validate_parameter_item(item.separator, formals, inside_argument: inside_argument)
      end
    end

    # @rbs (Frontend::AST::ParameterizedReference item, Array[String] formals, inside_argument: bool) -> void
    def validate_parameterized_item(item, formals, inside_argument:)
      # @type self: Normalizer
      if formals.include?(item.name)
        fail_at(item.loc, "formal #{item.name} cannot be used as a parameterized rule name")
      end
      validate_parameter_call(item)
      reject_argument_named_reference(item) if inside_argument && item.named_reference
      item.arguments.each { |argument| validate_parameter_item(argument, formals, inside_argument: true) }
    end

    # @rbs (Frontend::AST::SymbolReference | Frontend::AST::ParameterizedReference item) -> bot
    def reject_argument_named_reference(item)
      # @type self: Normalizer
      fail_at(item.loc, "named references are not allowed in parameter arguments")
    end

    # @rbs (Frontend::AST::ParameterizedReference reference) -> void
    def validate_parameter_call(reference)
      # @type self: Normalizer
      formals = @parameter_formals[reference.name]
      fail_at(reference.loc, "undefined parameterized rule #{reference.name}") unless formals
      return if reference.arguments.length == formals.length

      fail_at(
        reference.loc,
        "parameterized rule #{reference.name} expects #{formals.length} arguments, " \
        "got #{reference.arguments.length}"
      )
    end

    # @rbs (Frontend::AST::Rule rule) -> bool
    def parameterized_rule?(rule)
      !rule.parameters.empty?
    end

    # @rbs (String name) -> bool
    def parameter_template?(name)
      @parameter_templates.key?(name)
    end
  end
end
