# frozen_string_literal: true

module Ibex
  # Resumable, source-ordered lowering for specialized parameter alternatives.
  module NormalizeParameterLowering
    private

    # @rbs (Hash[Symbol, untyped] frame) -> void
    def advance_parameter_alternative(frame)
      # @type self: Normalizer
      with_parameter_frame_context(frame) do
        operations = frame.fetch(:operations)
        if operations.any?
          process_parameter_operation(frame, operations.pop)
        elsif parameter_items_remaining?(frame)
          start_parameter_item(frame)
        else
          finish_parameter_alternative(frame)
        end
      end
    end

    # @rbs (Hash[Symbol, untyped] frame) { () -> void } -> void
    def with_parameter_frame_context(frame)
      # @type self: Normalizer
      template, = frame.fetch(:current)
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

    # @rbs (Hash[Symbol, untyped] frame) -> bool
    def parameter_items_remaining?(frame)
      _template, _rule, alternative = frame.fetch(:current)
      frame.fetch(:item_index) < alternative.items.length
    end

    # @rbs (Hash[Symbol, untyped] frame) -> void
    def start_parameter_item(frame)
      # @type self: Normalizer
      _template, _rule, alternative = frame.fetch(:current)
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

    # @rbs (Hash[Symbol, untyped] frame, Array[untyped] operation) -> void
    def process_parameter_operation(frame, operation)
      # @type self: Normalizer
      kind, *arguments = operation
      case kind
      when :item then lower_parameter_item(frame, arguments.fetch(0))
      when :finish_item then finish_parameter_item(frame, arguments.fetch(0))
      when :value then frame.fetch(:values) << arguments.fetch(0)
      when :finish_suffix then finish_parameter_suffix(frame, arguments.fetch(0))
      when :finish_separated then finish_parameter_separated_list(frame, arguments.fetch(0))
      when :group_alternative
        start_parameter_group_alternative(frame, arguments.fetch(0), arguments.fetch(1), arguments.fetch(2))
      when :finish_group_alternative
        finish_parameter_group_alternative(frame, arguments.fetch(0), arguments.fetch(1), arguments.fetch(2))
      else raise Ibex::Error, "internal parameter lowering operation #{kind.inspect}"
      end
    end

    # @rbs (Hash[Symbol, untyped] frame, Frontend::AST::item item) -> void
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

    # @rbs (Hash[Symbol, untyped] frame, Frontend::AST::ParameterizedReference item) -> void
    def lower_parameter_call(frame, item)
      # @type self: Normalizer
      helper, = schedule_parameter_specialization(item)
      frame.fetch(:values) << helper
    end

    # @rbs (Hash[Symbol, untyped] frame, Frontend::AST::item item) -> void
    def finish_parameter_item(frame, item)
      # @type self: Normalizer
      rhs = frame.fetch(:rhs)
      rhs << frame.fetch(:values).pop
      add_named_reference(item, frame.fetch(:named_refs), rhs.length - 1)
    end

    # @rbs (Hash[Symbol, untyped] frame) -> void
    def finish_parameter_alternative(frame)
      # @type self: Normalizer
      _template, rule, alternative = frame.fetch(:current)
      action = normalize_action(alternative.action, frame.fetch(:named_refs))
      add_production(
        rule.lhs, frame.fetch(:rhs), action, alternative.precedence,
        { kind: :user, loc: alternative.loc.to_h }, rule.documentation
      )
      clear_parameter_alternative(frame)
    end
  end
end
