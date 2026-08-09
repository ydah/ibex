# frozen_string_literal: true

module Ibex
  # Resumable, source-ordered lowering for specialized parameter alternatives.
  module NormalizeParameterLowering
    private

    # @rbs (NormalizeParameters::parameter_frame frame) -> void
    def advance_parameter_alternative(frame)
      # @type self: Normalizer
      with_parameter_frame_context(frame) do
        operations = frame.fetch(:operations)
        if operations.any?
          operation = operations.pop #: NormalizeParameters::parameter_operation
          process_parameter_operation(frame, operation)
        elsif parameter_items_remaining?(frame)
          start_parameter_item(frame)
        else
          finish_parameter_alternative(frame)
        end
      end
    end

    # @rbs (NormalizeParameters::parameter_frame frame) { () -> void } -> void
    def with_parameter_frame_context(frame)
      # @type self: Normalizer
      template, = frame.fetch(:current) || raise(Ibex::Error, "missing parameter alternative")
      previous_chain = @current_include_chain
      previous_expansion = @current_parameter_expansion
      reference = frame.fetch(:reference)
      @current_include_chain = @resolution&.include_chain_for(template) || []
      @current_parameter_expansion = {
        rule: reference.name, arguments: frame.fetch(:rendered_arguments)
      }
      yield
    ensure
      @current_include_chain = previous_chain
      @current_parameter_expansion = previous_expansion
    end

    # @rbs (NormalizeParameters::parameter_frame frame) -> bool
    def parameter_items_remaining?(frame)
      _template, _rule, alternative = frame.fetch(:current) || raise(Ibex::Error, "missing parameter alternative")
      frame.fetch(:item_index) < alternative.items.length
    end

    # @rbs (NormalizeParameters::parameter_frame frame) -> void
    def start_parameter_item(frame)
      # @type self: Normalizer
      _template, _rule, alternative = frame.fetch(:current) || raise(Ibex::Error, "missing parameter alternative")
      index = frame.fetch(:item_index)
      item = alternative.items.fetch(index)
      frame[:item_index] = index + 1
      if item.is_a?(Frontend::AST::InlineAction)
        frame.fetch(:rhs) << expand_inline_action(
          item, frame.fetch(:rhs).length, frame.fetch(:named_refs)
        )
      else
        frame.fetch(:operations).push([:finish_item, item], [:item, item])
      end
    end

    # @rbs (NormalizeParameters::parameter_frame frame, NormalizeParameters::parameter_operation operation) -> void
    def process_parameter_operation(frame, operation)
      # @type self: Normalizer
      kind = operation.fetch(0) #: Symbol
      case kind
      when :item
        item = operation.fetch(1) #: Frontend::AST::item
        lower_parameter_item(frame, item)
      when :finish_item
        item = operation.fetch(1) #: Frontend::AST::item
        finish_parameter_item(frame, item)
      when :value
        value = operation.fetch(1) #: String
        frame.fetch(:values) << value
      when :finish_suffix
        item = operation.fetch(1) #: Frontend::AST::Optional | Frontend::AST::Star | Frontend::AST::Plus
        finish_parameter_suffix(frame, item)
      when :finish_separated
        item = operation.fetch(1) #: Frontend::AST::SeparatedList
        finish_parameter_separated_list(frame, item)
      when :group_alternative
        helper = operation.fetch(1) #: String
        item = operation.fetch(2) #: Frontend::AST::Group
        alternative = operation.fetch(3) #: Array[Frontend::AST::item]
        start_parameter_group_alternative(frame, helper, item, alternative)
      when :finish_group_alternative
        helper = operation.fetch(1) #: String
        item = operation.fetch(2) #: Frontend::AST::Group
        length = operation.fetch(3) #: Integer
        finish_parameter_group_alternative(frame, helper, item, length)
      else raise Ibex::Error, "internal parameter lowering operation #{kind.inspect}"
      end
    end

    # @rbs (NormalizeParameters::parameter_frame frame, Frontend::AST::item item) -> void
    def lower_parameter_item(frame, item)
      # @type self: Normalizer
      case item
      when Frontend::AST::SymbolReference
        frame.fetch(:values) << symbol_for_reference(item).name
      when Frontend::AST::ParameterizedReference
        lower_parameter_call(frame, item)
      when Frontend::AST::Group
        lower_parameter_group(frame, item)
      when Frontend::AST::Optional, Frontend::AST::Star, Frontend::AST::Plus
        lower_parameter_suffix(frame, item)
      when Frontend::AST::SeparatedList
        lower_parameter_separated_list(frame, item)
      else
        fail_at(item.loc, "unsupported nested EBNF expression")
      end
    end

    # @rbs (NormalizeParameters::parameter_frame frame, Frontend::AST::ParameterizedReference item) -> void
    def lower_parameter_call(frame, item)
      # @type self: Normalizer
      helper, = schedule_parameter_specialization(item)
      frame.fetch(:values) << helper
    end

    # @rbs (NormalizeParameters::parameter_frame frame, Frontend::AST::item item) -> void
    def finish_parameter_item(frame, item)
      # @type self: Normalizer
      rhs = frame.fetch(:rhs)
      rhs << (frame.fetch(:values).pop || raise(Ibex::Error, "missing parameter value"))
      add_named_reference(item, frame.fetch(:named_refs), rhs.length - 1)
    end

    # @rbs (NormalizeParameters::parameter_frame frame) -> void
    def finish_parameter_alternative(frame)
      # @type self: Normalizer
      _template, rule, alternative = frame.fetch(:current) || raise(Ibex::Error, "missing parameter alternative")
      action = normalize_action(alternative.action, frame.fetch(:named_refs))
      add_production(
        rule.lhs, frame.fetch(:rhs), action, alternative.precedence,
        { kind: :user, loc: alternative.loc.to_h }, rule.documentation
      )
      clear_parameter_alternative(frame)
    end
  end
end
