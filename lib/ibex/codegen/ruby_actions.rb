# frozen_string_literal: true
# rbs_inline: enabled

require_relative "action_method_source"
require_relative "ruby_ast"

module Ibex
  module Codegen
    # Semantic-action method generation shared by direct and source-mapped
    # Ruby output.
    module RubyActions
      include RubyAST

      # @rbs @grammar: IR::Grammar
      # @rbs @line_convert: bool
      # @rbs @omit_action_call: bool
      # @rbs @action_method_source: ActionMethodSource?

      private

      # @rbs (Array[String] lines) -> void
      def append_actions(lines)
        @grammar.productions.each do |production|
          next unless action_method?(production)

          if production.node
            source = ast_node_action_source(production)
            source.lines.each { |line| lines << "  #{line.rstrip}" }
            lines << ""
          elsif composed_action?(production)
            append_composed_action_method(lines, production)
          elsif production.action && @line_convert
            append_compiled_action_method(lines, production)
          else
            append_action_method(lines, production)
          end
        end
      end

      # @rbs (Array[String] lines, IR::Production production) -> void
      def append_composed_action_method(lines, production)
        action = production.action || raise(Ibex::Error, "missing composed semantic action")
        plan = action.composition&.dig(:plan) || raise(Ibex::Error, "missing action composition plan")
        steps = plan.fetch(:steps)
        steps.each_with_index do |step, index|
          append_composed_fragment_method(lines, production, step, index) if step[:code]
        end
        append_composed_orchestrator(lines, production, plan)
      end

      # @rbs (Array[String] lines, IR::Production production, IR::action_composition_step step, Integer index) -> void
      def append_composed_fragment_method(lines, production, step, index)
        source = action_method_source.composed_fragment_method_source(production, step, index)
        if @line_convert
          location = step.fetch(:loc)
          lines << "  class_eval(#{source.dump}, #{location[:file].inspect}, #{location[:line]})"
        else
          code = step.fetch(:code) #: String
          if action_method_source.column_sensitive?(code)
            lines << source
          else
            source.lines.each { |line| lines << "  #{line.rstrip}" }
          end
        end
        lines << ""
      end

      # @rbs (IR::Production production, Integer index) -> String
      def composed_fragment_name(production, index)
        action_method_source.composed_fragment_name(production, index)
      end

      # @rbs (Array[String] lines, IR::Production production, IR::action_composition_plan plan) -> void
      def append_composed_orchestrator(lines, production, plan)
        lines << "  private def _ibex_action_#{production.id}" \
                 "(val, _values, _ibex_locations, _ibex_location_stack, _ibex_location, " \
                 "_ibex_lookahead_location)"
        lines << "    _ibex_composed_values = val.dup"
        lines << "    _ibex_composed_locations = _ibex_locations.dup"
        plan.fetch(:steps).each_with_index do |step, index|
          append_composed_step(lines, production, step, index)
        end
        lines.push("    _ibex_composed_values.last", "  end", "")
      end

      # @rbs (Array[String] lines, IR::Production production, IR::action_composition_step step, Integer index) -> void
      def append_composed_step(lines, production, step, index)
        inputs = step.fetch(:inputs)
        lines << "    _ibex_step_values = _ibex_composed_values.values_at(#{inputs.join(', ')})"
        lines << "    _ibex_step_locations = _ibex_composed_locations.values_at(#{inputs.join(', ')})"
        lookahead = step[:lookahead]
        boundary = lookahead ? "_ibex_locations[#{lookahead}]" : "_ibex_lookahead_location"
        lines << "    _ibex_step_location = Ibex::Runtime::LocationSpan.for_reduction(" \
                 "_ibex_step_locations, lookahead: #{boundary})"
        result = if step[:code]
                   stack_inputs = step.fetch(:stack_inputs)
                   "#{composed_fragment_name(production, index)}(" \
                     "_ibex_step_values, _values + _ibex_composed_values.values_at(#{stack_inputs.join(', ')}), " \
                     "_ibex_step_locations, _ibex_location_stack + " \
                     "_ibex_composed_locations.values_at(#{stack_inputs.join(', ')}), _ibex_step_location)"
                 else
                   "_ibex_step_values[0]"
                 end
        lines << "    _ibex_composed_values << #{result}"
        lines << "    _ibex_composed_locations << _ibex_step_location"
        lines << "    return _ibex_composed_values.last if @accept_requested || @semantic_error"
      end

      # @rbs (Array[String] lines, IR::Production production) -> void
      def append_compiled_action_method(lines, production)
        action = production.action || raise(Ibex::Error, "missing semantic action")
        source = action_method_source.compiled_action_method_source(production)
        lines << "  class_eval(#{source.dump}, #{action.location[:file].inspect}, #{action.location[:line]})"
        lines << ""
      end

      # @rbs (Array[String] lines, IR::Production production) -> void
      def append_action_method(lines, production)
        source = action_method_source.direct_action_method_source(production)
        if production.action && action_method_source.column_sensitive?(production.action.code)
          lines << source
        else
          source.lines.each { |line| lines << "  #{line.rstrip}" }
        end
        lines << ""
      end

      # @rbs (IR::Production production) -> bool
      def action_method?(production)
        !!(production.node || production.action || !@omit_action_call)
      end

      # @rbs (IR::Production production) -> bool
      def composed_action?(production)
        production.action&.composition&.dig(:plan, :version) == 1
      end

      # @rbs () -> ActionMethodSource
      def action_method_source
        @action_method_source ||= ActionMethodSource.new(
          @grammar, generated_action_abi: @generated_action_abi
        )
      end
    end
  end
end
