# frozen_string_literal: true
# rbs_inline: enabled

require_relative "action_locations"

module Ibex
  module Codegen
    # Semantic-action method generation shared by direct and source-mapped
    # Ruby output.
    # rubocop:disable Metrics/ModuleLength -- action emission keeps shared naming and mapping invariants together.
    module RubyActions
      # @rbs @grammar: IR::Grammar
      # @rbs @line_convert: bool
      # @rbs @omit_action_call: bool

      private

      # @rbs (Array[String] lines) -> void
      def append_actions(lines)
        @grammar.productions.each do |production|
          next unless action_method?(production)

          if composed_action?(production)
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

      # @rbs (Array[String] lines, IR::Production production, Hash[Symbol, untyped] step, Integer index) -> void
      def append_composed_fragment_method(lines, production, step, index)
        source = composed_fragment_method_source(production, step, index)
        if @line_convert
          location = step.fetch(:loc)
          lines << "  class_eval(#{source.dump}, #{location[:file].inspect}, #{location[:line]})"
        else
          source.lines.each { |line| lines << "  #{line.rstrip}" }
        end
        lines << ""
      end

      # @rbs (IR::Production production, Hash[Symbol, untyped] step, Integer index) -> String
      def composed_fragment_method_source(production, step, index)
        source = "private def #{composed_fragment_name(production, index)}" \
                 "(val, _values, _ibex_locations, _ibex_location_stack, _ibex_location); "
        context_length = step.fetch(:context_length)
        if context_length.positive?
          source << "val = _values.last(#{context_length}); "
          source << "_ibex_locations = _ibex_location_stack.last(#{context_length}); "
        end
        named_refs = step.fetch(:named_refs)
        named_refs.each { |reference| source << "#{reference[:name]} = val[#{reference[:index]}]; " }
        unless named_refs.empty?
          names = named_refs.map { |reference| reference[:name] }
          source << "_ibex_named_values = [#{names.join(', ')}]; "
        end
        source << "result = val[0]; " if step.fetch(:result_var)
        source << composed_semantic_code(step)
        source << "\nresult" if step.fetch(:result_var)
        source << "\nend"
      end

      # @rbs (Hash[Symbol, untyped] step) -> String
      def composed_semantic_code(step)
        maximum = [step.fetch(:inputs).length, step.fetch(:context_length)].max
        ActionLocations.new(
          step.fetch(:code), maximum: maximum, location: step.fetch(:loc)
        ).rewrite
      end

      # @rbs (IR::Production production, Integer index) -> String
      def composed_fragment_name(production, index)
        "_ibex_inline_fragment_#{production.id}_#{index}"
      end

      # @rbs (Array[String] lines, IR::Production production, Hash[Symbol, untyped] plan) -> void
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

      # @rbs (Array[String] lines, IR::Production production, Hash[Symbol, untyped] step, Integer index) -> void
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

      # @rbs (IR::Production production) -> bool
      def composed_action?(production)
        production.action&.composition&.dig(:plan, :version) == 1
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
