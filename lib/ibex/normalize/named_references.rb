# frozen_string_literal: true

module Ibex
  # Named-reference collection and validation shared by ordinary and parameterized items.
  module NormalizeNamedReferences
    private

    # @rbs (Frontend::AST::Group group) -> void
    def reject_group_named_references(group)
      # @type self: Normalizer
      reference = group.alternatives.flatten.filter_map { |item| named_reference_in(item) }.first
      fail_at(reference.loc, "named references inside EBNF groups are not supported") if reference
    end

    # @rbs (Frontend::AST::item item) -> (Frontend::AST::SymbolReference | Frontend::AST::ParameterizedReference)?
    def named_reference_in(item)
      # @type self: Normalizer
      if (item.is_a?(Frontend::AST::SymbolReference) ||
          item.is_a?(Frontend::AST::ParameterizedReference)) && item.named_reference
        return item
      end
      if item.is_a?(Frontend::AST::Group)
        return item.alternatives.flatten.filter_map { |child| named_reference_in(child) }.first
      end
      if item.is_a?(Frontend::AST::Optional) || item.is_a?(Frontend::AST::Star) ||
         item.is_a?(Frontend::AST::Plus) || item.is_a?(Frontend::AST::SeparatedList)
        return named_reference_in(item.item)
      end

      nil
    end

    # @rbs (Frontend::AST::item item, Array[IR::named_ref] refs, Integer index) -> void
    def add_named_reference(item, refs, index)
      # @type self: Normalizer
      reference = unwrap_reference(item)
      return unless reference

      name = reference.named_reference
      return unless name

      fail_at(reference.loc, "reserved named reference #{name}") if Normalizer::RESERVED_NAMES.include?(name)
      fail_at(reference.loc, "duplicate named reference #{name}") if refs.any? { |entry| entry[:name] == name }
      refs << { name: name, index: index }
    end

    # @rbs (Frontend::AST::item item) -> (Frontend::AST::SymbolReference | Frontend::AST::ParameterizedReference)?
    def unwrap_reference(item)
      # @type self: Normalizer
      return item if item.is_a?(Frontend::AST::SymbolReference) ||
                     item.is_a?(Frontend::AST::ParameterizedReference)
      if item.is_a?(Frontend::AST::Optional) || item.is_a?(Frontend::AST::Star) ||
         item.is_a?(Frontend::AST::Plus) || item.is_a?(Frontend::AST::SeparatedList)
        return unwrap_reference(item.item)
      end

      nil
    end
  end
end
