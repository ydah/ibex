# frozen_string_literal: true

module Ibex
  # Iterative, hygienic specialization of validated parameterized user rules.
  module NormalizeParameters
    private

    # @rbs (Frontend::AST::ParameterizedReference reference) -> String
    def specialize_parameterized_reference(reference)
      # @type self: Normalizer
      depth = (@parameter_current_depth || 0) + 1
      helper, scheduled = schedule_parameter_specialization(reference, depth)
      if scheduled && @parameter_worklist_active
        raise Ibex::Error, "#{reference.loc}: internal parameter worklist ordering failure"
      end

      drain_parameter_worklist unless @parameter_worklist_active
      helper
    end

    # @rbs (Frontend::AST::ParameterizedReference reference, Integer depth) -> [String, bool]
    def schedule_parameter_specialization(reference, depth)
      # @type self: Normalizer
      arguments = reference.arguments
      rendered_arguments = arguments.map { |argument| NormalizeExpression.render(argument) }
      key = [reference.name, rendered_arguments] #: [String, Array[String]]
      existing = @parameter_specializations[key]
      return [existing, false] if existing

      enforce_parameter_limits!(reference, depth)
      helper = new_parameter_helper(reference)
      @parameter_specializations[key] = helper
      @parameter_worklist << parameter_frame(reference, helper, arguments, rendered_arguments, depth)
      [helper, true]
    end

    # @rbs (Frontend::AST::ParameterizedReference reference, Integer depth) -> void
    def enforce_parameter_limits!(reference, depth)
      # @type self: Normalizer
      if @parameter_specializations.length >= @max_parameter_specializations
        fail_at(
          reference.loc,
          "parameter specialization limit of #{@max_parameter_specializations} exceeded"
        )
      end
      return if depth <= @max_parameter_depth

      fail_at(reference.loc, "parameter expansion depth limit of #{@max_parameter_depth} exceeded")
    end

    # @rbs (Frontend::AST::ParameterizedReference reference) -> String
    def new_parameter_helper(reference)
      # @type self: Normalizer
      @helper_sequence += 1
      name = "$parameter_#{@helper_sequence}"
      intern(
        name, :nonterminal,
        location: reference.loc.to_h,
        documentation: @rule_documentation[reference.name],
        metadata_name: reference.name
      )
      name
    end

    # @rbs (Frontend::AST::ParameterizedReference reference, String helper,
    #   Array[Frontend::AST::item] arguments, Array[String] rendered_arguments, Integer depth) ->
    #   Hash[Symbol, untyped]
    def parameter_frame(reference, helper, arguments, rendered_arguments, depth)
      # @type self: Normalizer
      formals = @parameter_formals.fetch(reference.name)
      {
        reference: reference,
        helper: helper,
        bindings: formals.zip(arguments).to_h,
        rendered_arguments: rendered_arguments,
        templates: @parameter_templates.fetch(reference.name),
        template_index: 0,
        alternative_index: 0,
        current: nil,
        item_index: 0,
        rhs: [],
        named_refs: [],
        operations: [],
        values: [],
        depth: depth
      }
    end

    # @rbs () -> void
    def drain_parameter_worklist
      # @type self: Normalizer
      @parameter_worklist_active = true
      until @parameter_worklist.empty?
        frame = @parameter_worklist.last
        unless frame[:current] || prepare_parameter_alternative?(frame)
          @parameter_worklist.pop
          next
        end

        advance_parameter_alternative(frame)
      end
    ensure
      @parameter_worklist_active = false
    end

    # @rbs (Hash[Symbol, untyped] frame) -> bool
    def prepare_parameter_alternative?(frame)
      # @type self: Normalizer
      templates = frame.fetch(:templates)
      while frame.fetch(:template_index) < templates.length
        template = templates.fetch(frame.fetch(:template_index))
        index = frame.fetch(:alternative_index)
        if index < template.alternatives.length
          prepare_parameter_alternative_entry(frame, template, index)
          return true
        end
        frame[:template_index] += 1
        frame[:alternative_index] = 0
      end
      false
    end

    # @rbs (Hash[Symbol, untyped] frame, Frontend::AST::Rule template, Integer index) -> void
    def prepare_parameter_alternative_entry(frame, template, index)
      # @type self: Normalizer
      alternative = substitute_parameter_alternative(
        template.alternatives.fetch(index), frame.fetch(:bindings)
      )
      rule = Frontend::AST::Rule.new(
        lhs: frame.fetch(:helper), parameters: [], alternatives: [alternative], loc: template.loc,
        documentation: template.documentation
      )
      frame[:alternative_index] = index + 1
      frame[:current] = [template, rule, alternative]
      frame[:item_index] = 0
      frame[:rhs] = []
      frame[:named_refs] = []
      frame[:operations] = []
      frame[:values] = []
    end

    # @rbs (Hash[Symbol, untyped] frame) -> void
    def clear_parameter_alternative(frame)
      frame[:current] = nil
      frame[:item_index] = 0
      frame[:rhs] = []
      frame[:named_refs] = []
      frame[:operations] = []
      frame[:values] = []
    end
  end
end
