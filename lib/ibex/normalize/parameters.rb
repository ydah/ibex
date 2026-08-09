# frozen_string_literal: true

module Ibex
  # Iterative, hygienic specialization of validated parameterized user rules.
  module NormalizeParameters
    # @rbs!
    #   type parameter_operation =
    #     [:item | :finish_item, Frontend::AST::item] |
    #     [:value, String] |
    #     [:finish_suffix, Frontend::AST::Optional | Frontend::AST::Star | Frontend::AST::Plus] |
    #     [:finish_separated, Frontend::AST::SeparatedList] |
    #     [:group_alternative, String, Frontend::AST::Group, Array[Frontend::AST::item]] |
    #     [:finish_group_alternative, String, Frontend::AST::Group, Integer]
    #   type parameter_frame = {
    #     reference: Frontend::AST::ParameterizedReference,
    #     arguments: Array[Frontend::AST::item],
    #     helper: String,
    #     bindings: Hash[String, Frontend::AST::item],
    #     rendered_arguments: Array[String],
    #     templates: Array[Frontend::AST::Rule],
    #     template_index: Integer,
    #     alternative_index: Integer,
    #     current: [Frontend::AST::Rule, Frontend::AST::Rule, Frontend::AST::Alternative]?,
    #     item_index: Integer,
    #     rhs: Array[String],
    #     named_refs: Array[IR::named_ref],
    #     operations: Array[parameter_operation],
    #     values: Array[String]
    #   }

    private

    # @rbs (Frontend::AST::ParameterizedReference reference) -> String
    def specialize_parameterized_reference(reference)
      # @type self: Normalizer
      helper, scheduled = schedule_parameter_specialization(reference)
      if scheduled && @parameter_worklist_active
        raise Ibex::Error, "#{reference.loc}: internal parameter worklist ordering failure"
      end

      drain_parameter_worklist unless @parameter_worklist_active
      helper
    end

    # @rbs (Frontend::AST::ParameterizedReference reference) -> [String, bool]
    def schedule_parameter_specialization(reference)
      # @type self: Normalizer
      arguments = reference.arguments
      rendered_arguments = arguments.map { |argument| NormalizeExpression.render(argument) }
      key = [reference.name, rendered_arguments] #: [String, Array[String]]
      existing = @parameter_specializations[key]
      return [existing, false] if existing

      enforce_parameter_limits!(reference)
      helper = new_parameter_helper(reference)
      @parameter_specializations[key] = helper
      @parameter_worklist << parameter_frame(reference, helper, arguments, rendered_arguments)
      [helper, true]
    end

    # @rbs (Frontend::AST::ParameterizedReference reference) -> void
    def enforce_parameter_limits!(reference)
      # @type self: Normalizer
      cyclic = @parameter_worklist.reverse.find do |frame|
        frame.fetch(:reference).name == reference.name &&
          growing_parameter_arguments?(reference.arguments, frame.fetch(:arguments))
      end
      if cyclic
        path = (@parameter_worklist.drop_while { |frame| frame != cyclic } + [{ reference: reference }])
               .map { |frame| frame.fetch(:reference).name }
        fail_at(reference.loc, "cyclic parameter specialization #{path.join(' -> ')}")
      end
      return unless @parameter_specializations.length >= @max_parameter_specializations

      fail_at(
        reference.loc,
        "parameter specialization limit of #{@max_parameter_specializations} exceeded"
      )
    end

    # A constructor-growing recursive call can create infinitely many distinct
    # specializations. Calls whose arguments shrink or merely change are
    # allowed; they may reach a memoized fixed point after finite expansion.
    # @rbs (Array[Frontend::AST::item] candidates, Array[Frontend::AST::item] ancestors) -> bool
    def growing_parameter_arguments?(candidates, ancestors)
      return false unless candidates.length == ancestors.length

      contained = candidates.each_index.all? do |index|
        candidate = candidates.fetch(index)
        ancestor = ancestors.fetch(index)
        parameter_argument_contains?(candidate, NormalizeExpression.render(ancestor))
      end
      contained && candidates.each_index.any? do |index|
        candidate = candidates.fetch(index)
        ancestor = ancestors.fetch(index)
        NormalizeExpression.render(candidate) != NormalizeExpression.render(ancestor)
      end
    end

    # @rbs (Frontend::AST::item candidate, String target) -> bool
    def parameter_argument_contains?(candidate, target)
      pending = [candidate] #: Array[Frontend::AST::item]
      until pending.empty?
        item = pending.pop
        raise Ibex::Error, "missing parameter argument" unless item

        return true if NormalizeExpression.render(item) == target

        case item
        when Frontend::AST::ParameterizedReference then pending.concat(item.arguments)
        when Frontend::AST::Group then item.alternatives.each { |alternative| pending.concat(alternative) }
        when Frontend::AST::Optional, Frontend::AST::Star, Frontend::AST::Plus then pending << item.item
        when Frontend::AST::SeparatedList then pending.push(item.item, item.separator)
        end
      end
      false
    end

    # @rbs (Frontend::AST::ParameterizedReference reference) -> String
    def new_parameter_helper(reference)
      # @type self: Normalizer
      @helper_sequence += 1
      name = "$parameter_#{@helper_sequence}"
      definition = intern(
        name, :nonterminal,
        location: reference.loc.to_h,
        documentation: @rule_documentation[reference.name],
        metadata_name: reference.name
      )
      if @inline_rule_names.include?(reference.name)
        @inline_symbol_ids << definition.id
        @inline_rule_by_symbol[definition.id] = reference.name
      end
      name
    end

    # @rbs (Frontend::AST::ParameterizedReference reference, String helper,
    #   Array[Frontend::AST::item] arguments, Array[String] rendered_arguments) ->
    #   NormalizeParameters::parameter_frame
    def parameter_frame(reference, helper, arguments, rendered_arguments)
      # @type self: Normalizer
      formals = @parameter_formals.fetch(reference.name)
      {
        reference: reference,
        arguments: arguments,
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
        values: []
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

    # @rbs (NormalizeParameters::parameter_frame frame) -> bool
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

    # @rbs (NormalizeParameters::parameter_frame frame, Frontend::AST::Rule template, Integer index) -> void
    def prepare_parameter_alternative_entry(frame, template, index)
      # @type self: Normalizer
      alternative = substitute_parameter_alternative(
        template.alternatives.fetch(index), frame.fetch(:bindings)
      )
      rule = Frontend::AST::Rule.new(
        lhs: frame.fetch(:helper), parameters: [], alternatives: [alternative], loc: template.loc,
        documentation: template.documentation, inline: false
      )
      frame[:alternative_index] = index + 1
      frame[:current] = [template, rule, alternative]
      frame[:item_index] = 0
      frame[:rhs] = []
      frame[:named_refs] = []
      frame[:operations] = []
      frame[:values] = []
    end

    # @rbs (NormalizeParameters::parameter_frame frame) -> void
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
