# frozen_string_literal: true
# rbs_inline: enabled

require_relative "action_locations"

module Ibex
  module Codegen
    # Semantic-action method generation shared by direct and source-mapped
    # Ruby output.
    module RubyActions
      # @rbs @grammar: IR::Grammar
      # @rbs @line_convert: bool
      # @rbs @omit_action_call: bool

      private

      # @rbs (Array[String] lines) -> void
      def append_actions(lines)
        @grammar.productions.each do |production|
          next unless action_method?(production)

          if production.action && @line_convert
            append_compiled_action_method(lines, production)
          else
            append_action_method(lines, production)
          end
        end
      end

      # @rbs (Array[String] lines, IR::Production production) -> void
      def append_compiled_action_method(lines, production)
        action = production.action || raise(Ibex::Error, "missing semantic action")
        source = compiled_action_method_source(production, action)
        lines << "  class_eval(#{source.dump}, #{action.location[:file].inspect}, #{action.location[:line]})"
        lines << ""
      end

      # @rbs (IR::Production production, IR::Action action) -> String
      def compiled_action_method_source(production, action)
        source = "private def _ibex_action_#{production.id}" \
                 "(val, _values, _ibex_locations, _ibex_location_stack, _ibex_location); "
        if action.context_length.positive?
          source << "val = _values.last(#{action.context_length}); "
          source << "_ibex_locations = _ibex_location_stack.last(#{action.context_length}); "
        end
        action.named_refs.each { |reference| source << "#{reference[:name]} = val[#{reference[:index]}]; " }
        append_named_values(source, action)
        append_action_body(source, production, action)
        source << "\nend"
      end

      # @rbs (String source, IR::Action action) -> void
      def append_named_values(source, action)
        return if action.named_refs.empty?

        names = action.named_refs.map { |reference| reference[:name] }
        source << "_ibex_named_values = [#{names.join(', ')}]; "
      end

      # @rbs (String source, IR::Production production, IR::Action action) -> void
      def append_action_body(source, production, action)
        source << "result = val[0]; " if @grammar.options[:result_var]
        source << semantic_action_code(production, action)
        source << "\nresult" if @grammar.options[:result_var]
      end

      # @rbs (Array[String] lines, IR::Production production) -> void
      def append_action_method(lines, production)
        action = production.action
        lines << "  private def _ibex_action_#{production.id}" \
                 "(val, _values, _ibex_locations, _ibex_location_stack, _ibex_location)"
        append_middle_action_context(lines, action)
        append_named_bindings(lines, action)
        action ? append_semantic_code(lines, production) : lines << "    val[0]"
        lines.push("  end", "")
      end

      # @rbs (Array[String] lines, IR::Action? action) -> void
      def append_middle_action_context(lines, action)
        return unless action&.context_length&.positive?

        lines << "    val = _values.last(#{action.context_length})"
        lines << "    _ibex_locations = _ibex_location_stack.last(#{action.context_length})"
      end

      # @rbs (Array[String] lines, IR::Action? action) -> void
      def append_named_bindings(lines, action)
        return unless action&.named_refs&.any?

        action.named_refs.each { |reference| lines << "    #{reference[:name]} = val[#{reference[:index]}]" }
        names = action.named_refs.map { |reference| reference[:name] }
        lines << "    _ibex_named_values = [#{names.join(', ')}]"
      end

      # @rbs (Array[String] lines, IR::Production production) -> void
      def append_semantic_code(lines, production)
        action = production.action || raise(Ibex::Error, "missing semantic action")
        lines << "    result = val[0]" if @grammar.options[:result_var]
        semantic_action_code(production, action).lines.each { |line| lines << "    #{line.rstrip}" }
        lines << "    result" if @grammar.options[:result_var]
      end

      # @rbs (IR::Production production, IR::Action action) -> String
      def semantic_action_code(production, action)
        maximum = action.context_length.positive? ? action.context_length : production.rhs.length
        ActionLocations.new(action.code, maximum: maximum, location: action.location).rewrite
      end

      # @rbs (IR::Production production) -> bool
      def action_method?(production)
        !!(production.action || !@omit_action_call)
      end
    end
  end
end
