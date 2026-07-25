# frozen_string_literal: true

module Ibex
  # Structural, sharing-preserving substitution for parameterized user rules.
  module NormalizeParameterSubstitution
    private

    # @rbs (Frontend::AST::Alternative alternative, Hash[String, Frontend::AST::item] bindings) ->
    #   Frontend::AST::Alternative
    def substitute_parameter_alternative(alternative, bindings)
      # @type self: Normalizer
      Frontend::AST::Alternative.new(
        items: alternative.items.map { |item| substitute_parameter_item(item, bindings) },
        action: alternative.action, precedence: substitute_parameter_precedence(alternative, bindings),
        loc: alternative.loc
      )
    end

    # @rbs (Frontend::AST::Alternative alternative, Hash[String, Frontend::AST::item] bindings) -> String?
    def substitute_parameter_precedence(alternative, bindings)
      # @type self: Normalizer
      precedence = alternative.precedence
      return precedence unless precedence && bindings.key?(precedence)

      argument = bindings.fetch(precedence)
      unless argument.is_a?(Frontend::AST::SymbolReference) && !argument.named_reference
        fail_at(alternative.loc, "formal precedence #{precedence} requires one plain symbol argument")
      end
      argument.name
    end

    # @rbs (Frontend::AST::item item, Hash[String, Frontend::AST::item] bindings) -> Frontend::AST::item
    def substitute_parameter_item(item, bindings)
      # @type self: Normalizer
      if item.is_a?(Frontend::AST::SymbolReference) && bindings.key?(item.name)
        return substitute_formal_reference(item, bindings.fetch(item.name))
      end

      clone_parameter_item(item, bindings)
    end

    # @rbs (Frontend::AST::SymbolReference formal, Frontend::AST::item argument) -> Frontend::AST::item
    def substitute_formal_reference(formal, argument)
      # @type self: Normalizer
      name = formal.named_reference
      return argument unless name

      case argument
      when Frontend::AST::SymbolReference
        Frontend::AST::SymbolReference.new(name: argument.name, named_reference: name, loc: argument.loc)
      when Frontend::AST::ParameterizedReference
        Frontend::AST::ParameterizedReference.new(
          name: argument.name, arguments: argument.arguments, named_reference: name, loc: argument.loc
        )
      else
        fail_at(formal.loc, "named formal #{formal.name} requires a plain symbol or parameterized argument")
      end
    end

    # @rbs (Frontend::AST::item item, ?Hash[String, Frontend::AST::item] bindings) -> Frontend::AST::item
    def clone_parameter_item(item, bindings = {})
      # @type self: Normalizer
      case item
      when Frontend::AST::SymbolReference
        clone_parameter_symbol(item, bindings)
      when Frontend::AST::ParameterizedReference
        clone_parameter_call(item, bindings)
      when Frontend::AST::Group
        clone_parameter_group(item, bindings)
      when Frontend::AST::Optional, Frontend::AST::Star, Frontend::AST::Plus
        clone_parameter_suffix(item, bindings)
      when Frontend::AST::SeparatedList
        clone_parameter_separated_list(item, bindings)
      else
        item
      end
    end

    # @rbs (Frontend::AST::SymbolReference item, Hash[String, Frontend::AST::item] bindings) -> Frontend::AST::item
    def clone_parameter_symbol(item, bindings)
      # @type self: Normalizer
      return substitute_parameter_item(item, bindings) if bindings.key?(item.name)

      Frontend::AST::SymbolReference.new(name: item.name, named_reference: item.named_reference, loc: item.loc)
    end

    # @rbs (Frontend::AST::ParameterizedReference item, Hash[String, Frontend::AST::item] bindings) ->
    #   Frontend::AST::ParameterizedReference
    def clone_parameter_call(item, bindings)
      # @type self: Normalizer
      fail_at(item.loc, "formal #{item.name} cannot be used as a parameterized rule name") if bindings.key?(item.name)
      Frontend::AST::ParameterizedReference.new(
        name: item.name, arguments: item.arguments.map { |argument| substitute_parameter_item(argument, bindings) },
        named_reference: item.named_reference, loc: item.loc
      )
    end

    # @rbs (Frontend::AST::Group item, Hash[String, Frontend::AST::item] bindings) -> Frontend::AST::Group
    def clone_parameter_group(item, bindings)
      # @type self: Normalizer
      alternatives = item.alternatives.map do |items|
        items.map { |child| substitute_parameter_item(child, bindings) }
      end
      Frontend::AST::Group.new(alternatives: alternatives, loc: item.loc)
    end

    # @rbs (Frontend::AST::Optional | Frontend::AST::Star | Frontend::AST::Plus item,
    #   Hash[String, Frontend::AST::item] bindings) -> Frontend::AST::item
    def clone_parameter_suffix(item, bindings)
      # @type self: Normalizer
      item.class.new(item: substitute_parameter_item(item.item, bindings), loc: item.loc)
    end

    # @rbs (Frontend::AST::SeparatedList item, Hash[String, Frontend::AST::item] bindings) ->
    #   Frontend::AST::SeparatedList
    def clone_parameter_separated_list(item, bindings)
      # @type self: Normalizer
      Frontend::AST::SeparatedList.new(
        item: substitute_parameter_item(item.item, bindings),
        separator: substitute_parameter_item(item.separator, bindings),
        nonempty: item.nonempty, loc: item.loc
      )
    end
  end
end
