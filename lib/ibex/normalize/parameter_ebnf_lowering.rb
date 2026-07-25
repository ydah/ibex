# frozen_string_literal: true

module Ibex
  # Resumable EBNF lowering used inside specialized parameter alternatives.
  module NormalizeParameterEbnfLowering
    private

    # @rbs (Hash[Symbol, untyped] frame,
    #   Frontend::AST::Optional | Frontend::AST::Star | Frontend::AST::Plus item) -> void
    def lower_parameter_suffix(frame, item)
      frame.fetch(:operations).push([:finish_suffix, item], [:item, item.item])
    end

    # @rbs (Hash[Symbol, untyped] frame,
    #   Frontend::AST::Optional | Frontend::AST::Star | Frontend::AST::Plus item) -> void
    def finish_parameter_suffix(frame, item)
      # @type self: Normalizer
      base = frame.fetch(:values).pop
      helper = case item
               when Frontend::AST::Optional then build_optional(item, base)
               when Frontend::AST::Star then build_star(item, base)
               when Frontend::AST::Plus then build_plus(item, base)
               end
      frame.fetch(:values) << helper
    end

    # @rbs (Hash[Symbol, untyped] frame, Frontend::AST::SeparatedList item) -> void
    def lower_parameter_separated_list(frame, item)
      frame.fetch(:operations).push(
        [:finish_separated, item], [:item, item.separator], [:item, item.item]
      )
    end

    # @rbs (Hash[Symbol, untyped] frame, Frontend::AST::SeparatedList item) -> void
    def finish_parameter_separated_list(frame, item)
      # @type self: Normalizer
      separator = frame.fetch(:values).pop
      base = frame.fetch(:values).pop
      frame.fetch(:values) << build_separated_list(item, base, separator)
    end

    # @rbs (Hash[Symbol, untyped] frame, Frontend::AST::Group item) -> void
    def lower_parameter_group(frame, item)
      # @type self: Normalizer
      reject_group_named_references(item)
      helper = new_helper("group", item.loc)
      operations = frame.fetch(:operations)
      operations << [:value, helper]
      item.alternatives.reverse_each do |alternative|
        operations << [:group_alternative, helper, item, alternative]
      end
    end

    # @rbs (Hash[Symbol, untyped] frame, String helper, Frontend::AST::Group item,
    #   Array[Frontend::AST::item] alternative) -> void
    def start_parameter_group_alternative(frame, helper, item, alternative)
      operations = frame.fetch(:operations)
      operations << [:finish_group_alternative, helper, item, alternative.length]
      alternative.reverse_each { |child| operations << [:item, child] }
    end

    # @rbs (Hash[Symbol, untyped] frame, String helper, Frontend::AST::Group item, Integer length) -> void
    def finish_parameter_group_alternative(frame, helper, item, length)
      # @type self: Normalizer
      rhs = frame.fetch(:values).pop(length)
      add_group_production(helper, rhs, item)
    end
  end
end
