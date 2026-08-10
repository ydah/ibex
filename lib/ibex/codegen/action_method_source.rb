# frozen_string_literal: true
# rbs_inline: enabled

require_relative "action_locations"
require_relative "generated_action_abi"

module Ibex
  module Codegen
    # Builds semantic method source shared by runtime and static shadow output.
    class ActionMethodSource
      # @rbs @grammar: IR::Grammar
      # @rbs @generated_action_abi: GeneratedActionABI::Cache

      # @rbs (IR::Grammar grammar, ?generated_action_abi: GeneratedActionABI::Cache?) -> void
      def initialize(grammar, generated_action_abi: nil)
        @grammar = grammar
        @generated_action_abi = generated_action_abi || GeneratedActionABI::Cache.new
      end

      # @rbs (IR::Production production, IR::action_composition_step step, Integer index) -> String
      def composed_fragment_method_source(production, step, index)
        source = "private def #{composed_fragment_name(production, index)}" \
                 "(val, _values, _ibex_locations, _ibex_location_stack, _ibex_location); "
        append_parameter_values(source)
        context_length = step.fetch(:context_length)
        if context_length.positive?
          source << "val = _values.last(#{context_length}); "
          source << "_ibex_locations = _ibex_location_stack.last(#{context_length}); "
        end
        named_refs = step.fetch(:named_refs)
        named_refs.each { |reference| source << "#{reference[:name]} = val[#{reference[:index]}]; " }
        append_named_values(source, named_refs)
        source << "result = val[0]; " if step.fetch(:result_var)
        source << composed_semantic_code(step)
        source << "\nresult" if step.fetch(:result_var)
        source << "\nend"
      end

      # @rbs (IR::Production production, Integer index) -> String
      def composed_fragment_name(production, index)
        "_ibex_inline_fragment_#{production.id}_#{index}"
      end

      # @rbs (IR::Production production) -> String
      def compiled_action_method_source(production)
        action = production.action
        source = "private def _ibex_action_#{production.id}#{action_parameters(production)}; "
        append_parameter_values(source, production: production)
        return "#{source}#{default_value_expression(production)}\nend" unless action

        if action.context_length.positive?
          source << "val = _values.last(#{action.context_length}); "
          source << "_ibex_locations = _ibex_location_stack.last(#{action.context_length}); "
        end
        action.named_refs.each do |reference|
          source << "#{reference[:name]} = #{value_expression(production, reference[:index])}; "
        end
        append_named_values(source, action.named_refs)
        append_action_body(source, production, action)
        source << "\nend"
      end

      # @rbs (IR::Production production) -> String
      def direct_action_method_source(production)
        action = production.action
        lines = [
          "private def _ibex_action_#{production.id}#{action_parameters(production)}"
        ]
        append_direct_parameter_values(lines, production: production)
        if action&.context_length&.positive?
          lines << "  val = _values.last(#{action.context_length})"
          lines << "  _ibex_locations = _ibex_location_stack.last(#{action.context_length})"
        end
        if action&.named_refs&.any?
          action.named_refs.each do |reference|
            lines << "  #{reference[:name]} = #{value_expression(production, reference[:index])}"
          end
          names = action.named_refs.map { |reference| reference[:name] }
          lines << "  _ibex_named_values = [#{names.join(', ')}]"
        end
        append_direct_action_body(lines, production, action)
        lines << "end"
        lines.join("\n")
      end

      # @rbs (Integer symbol_id, IR::value_printer printer) -> String
      def value_printer_method_source(symbol_id, printer)
        source = "private def _ibex_value_printer_#{symbol_id}(value); "
        append_parameter_values(source)
        source << printer[:code]
        source << "\nend"
      end

      # @rbs (String source) -> bool
      def column_sensitive?(source)
        return false unless source.include?("<<")

        require "ripper"
        tokens = Object.const_get(:Ripper).__send__(:lex, source)
        # @type var tokens: Array[GeneratedActionABI::ripper_token]
        tokens.any? { |_position, event, _token, _state| event == :on_heredoc_beg }
      end

      private

      # @rbs (IR::Production production) -> String
      def action_parameters(production)
        if @generated_action_abi.positional_values?(production)
          parameters = Array.new(production.rhs.length) { |index| "v#{index}" }
          return "(#{parameters.join(', ')})"
        end
        return "(val)" if @generated_action_abi.values_only?(production)

        "(val, _values, _ibex_locations, _ibex_location_stack, _ibex_location)"
      end

      # @rbs (IR::Production production, Integer index) -> String
      def value_expression(production, index)
        return "v#{index}" if @generated_action_abi.positional_values?(production)

        "val[#{index}]"
      end

      # @rbs (String source, ?production: IR::Production?) -> void
      def append_parameter_values(source, production: nil)
        excluded = if production && @generated_action_abi.positional_values?(production)
                     Array.new(production.rhs.length) { |index| "v#{index}" }
                   else
                     [] #: Array[String]
                   end
        @grammar.parser_parameters.each do |parameter|
          next if excluded.include?(parameter[:name])

          source << "#{parameter[:name]} = @#{parameter[:name]}; "
        end
      end

      # @rbs (Array[String] lines, production: IR::Production) -> void
      def append_direct_parameter_values(lines, production:)
        excluded = if @generated_action_abi.positional_values?(production)
                     Array.new(production.rhs.length) { |index| "v#{index}" }
                   else
                     [] #: Array[String]
                   end
        @grammar.parser_parameters.each do |parameter|
          next if excluded.include?(parameter[:name])

          lines << "  #{parameter[:name]} = @#{parameter[:name]}"
        end
      end

      # @rbs (IR::action_composition_step step) -> String
      def composed_semantic_code(step)
        maximum = [step.fetch(:inputs).length, step.fetch(:context_length)].max
        ActionLocations.new(
          step.fetch(:code), maximum: maximum, location: step.fetch(:loc)
        ).rewrite
      end

      # @rbs (String source, Array[IR::named_ref] named_refs) -> void
      def append_named_values(source, named_refs)
        return if named_refs.empty?

        names = named_refs.map { |reference| reference[:name] }
        source << "_ibex_named_values = [#{names.join(', ')}]; "
      end

      # @rbs (String source, IR::Production production, IR::Action action) -> void
      def append_action_body(source, production, action)
        source << "result = #{default_value_expression(production)}; " if @grammar.options[:result_var]
        source << semantic_action_code(production, action)
        source << "\nresult" if @grammar.options[:result_var]
      end

      # @rbs (Array[String] lines, IR::Production production, IR::Action? action) -> void
      def append_direct_action_body(lines, production, action)
        unless action
          lines << "  #{default_value_expression(production)}"
          return
        end

        lines << "  result = #{default_value_expression(production)}" if @grammar.options[:result_var]
        semantic_code = semantic_action_code(production, action)
        if column_sensitive?(semantic_code)
          lines << semantic_code
        else
          semantic_code.lines.each { |line| lines << "  #{line.rstrip}" }
        end
        lines << "  result" if @grammar.options[:result_var]
      end

      # @rbs (IR::Production production, IR::Action action) -> String
      def semantic_action_code(production, action)
        positional = @generated_action_abi.positional_action_source(production)
        return positional unless positional.nil?

        maximum = action.context_length.positive? ? action.context_length : production.rhs.length
        ActionLocations.new(action.code, maximum: maximum, location: action.location).rewrite
      end

      # @rbs (IR::Production production) -> String
      def default_value_expression(production)
        return "nil" if production.rhs.empty?
        return "v0" if @generated_action_abi.positional_values?(production)

        "val[0]"
      end
    end
  end
end
