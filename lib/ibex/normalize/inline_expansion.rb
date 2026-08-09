# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Deterministically substitutes inline-rule productions before LR construction.
  # rubocop:disable Metrics/ModuleLength -- expansion, action plans, and id remapping share one invariant.
  module NormalizeInlineExpansion
    # @rbs!
    #   type inline_reference = [:physical | :step, Integer]
    #   type inline_step = {
    #     kind: :inline | :rule,
    #     rule: String?,
    #     code: String?,
    #     loc: IR::location,
    #     named_refs: Array[IR::named_ref],
    #     context_length: Integer,
    #     inputs: Array[inline_reference],
    #     stack_inputs: Array[inline_reference],
    #     lookahead: Integer,
    #     result_var: bool,
    #     result_type: String?
    #   }
    #   type inline_variant = {
    #     rhs: Array[Integer],
    #     steps: Array[inline_step],
    #     logical_refs: Array[inline_reference],
    #     output_ref: inline_reference?,
    #     inline_used: bool,
    #     inline_rule: String?,
    #     precedence_override: Integer?,
    #     precedence_contributes: bool,
    #     parameter: IR::parameter_expansion?
    #   }
    #   type inline_frame = {
    #     production: IR::Production,
    #     symbol_id: Integer?,
    #     index: Integer,
    #     variant: inline_variant
    #   }

    private

    # @rbs () -> void
    def expand_inline_rules
      # @type self: Normalizer
      return if @inline_symbol_ids.empty?

      definitions = @productions.group_by(&:lhs)
      expanded = [] #: Array[IR::Production]
      @productions.each do |production|
        next if @inline_symbol_ids.include?(production.lhs)

        variants = expand_inline_production(production, definitions)
        variants.each do |variant|
          if variant[:inline_used]
            charge_inline_expansion!(production)
            expanded << composed_inline_production(production, variant, expanded.length)
          else
            expanded << copy_inline_production(production, expanded.length)
          end
        end
      end
      rebuild_inline_symbols(expanded)
    end

    # Explicit heap frames avoid tying grammar depth to the Ruby call stack.
    # The single-definition path reuses its accumulated arrays, so a long
    # acyclic chain remains linear in the size of its final action plan.
    # @rbs (IR::Production production, Hash[Integer, Array[IR::Production]] definitions) ->
    #   Array[inline_variant]
    def expand_inline_production(production, definitions)
      # @type self: Normalizer
      variants = [] #: Array[inline_variant]
      worklist = [[inline_expansion_frame(production, nil)]] #: Array[Array[inline_frame]]
      until worklist.empty?
        frames = worklist.pop || raise(Ibex::Error, "internal inline expansion worklist underflow")
        drain_inline_expansion_frames(frames, definitions, worklist, variants, production.origin[:loc])
      end
      variants
    end

    # @rbs (Array[inline_frame] frames, Hash[Integer, Array[IR::Production]] definitions,
    #   Array[Array[inline_frame]] worklist, Array[inline_variant] variants,
    #   IR::location? location) -> void
    def drain_inline_expansion_frames(frames, definitions, worklist, variants, location)
      loop do
        frame = frames.fetch(-1)
        current = frame.fetch(:production)
        if frame.fetch(:index) < current.rhs.length
          return if advance_inline_expansion_frame?(frames, definitions, worklist, variants, location)
        elsif complete_inline_expansion_frame?(frames, variants, worklist, location)
          return
        end
      end
    end

    # @rbs (Array[inline_frame] frames, Hash[Integer, Array[IR::Production]] definitions,
    #   Array[Array[inline_frame]] worklist, Array[inline_variant] variants,
    #   IR::location? location) -> bool
    def advance_inline_expansion_frame?(frames, definitions, worklist, variants, location)
      frame = frames.fetch(-1)
      current = frame.fetch(:production)
      index = frame.fetch(:index)
      symbol_id = current.rhs.fetch(index)
      frame[:index] = index + 1
      unless @inline_symbol_ids.include?(symbol_id)
        frame[:variant] = append_inline_symbol(frame.fetch(:variant), symbol_id)
        return false
      end

      choices = definitions.fetch(symbol_id)
      if choices.one?
        frames << inline_expansion_frame(choices.fetch(0), symbol_id)
        return false
      end

      schedule_inline_choice_branches(frames, choices, symbol_id, worklist)
      enforce_inline_choice_limit!(variants.length + worklist.length, location)
      true
    end

    # @rbs (Array[inline_frame] frames, Array[IR::Production] choices, Integer symbol_id,
    #   Array[Array[inline_frame]] worklist) -> void
    def schedule_inline_choice_branches(frames, choices, symbol_id, worklist)
      choices.reverse_each do |choice|
        branch = clone_inline_expansion_frames(frames)
        branch << inline_expansion_frame(choice, symbol_id)
        worklist << branch
      end
    end

    # @rbs (Array[inline_frame] frames, Array[inline_variant] variants,
    #   Array[Array[inline_frame]] worklist, IR::location? location) -> bool
    def complete_inline_expansion_frame?(frames, variants, worklist, location)
      frame = frames.fetch(-1)
      current = frame.fetch(:production)
      completed = finish_inline_precedence(frame.fetch(:variant), current)
      frames.pop
      if frames.empty?
        variants << completed
        enforce_inline_choice_limit!(variants.length + worklist.length, location)
        return true
      end

      symbol_id = frame.fetch(:symbol_id) || raise(Ibex::Error, "inline expansion frame is missing its symbol")
      choice = finish_inline_choice(completed, current, symbol_id)
      parent = frames.fetch(-1)
      parent[:variant] = combine_inline_variant(parent.fetch(:variant), choice)
      false
    end

    # @rbs (IR::Production production, Integer? symbol_id) -> inline_frame
    def inline_expansion_frame(production, symbol_id)
      { production: production, symbol_id: symbol_id, index: 0, variant: empty_inline_variant(production) }
    end

    # @rbs (Array[inline_frame] frames) -> Array[inline_frame]
    def clone_inline_expansion_frames(frames)
      frames.map do |frame|
        variant = frame.fetch(:variant)
        cloned = frame.merge(
          variant: variant.merge(
            rhs: variant.fetch(:rhs).dup,
            steps: variant.fetch(:steps).dup,
            logical_refs: variant.fetch(:logical_refs).dup
          )
        )
        cloned #: inline_frame
      end
    end

    # @rbs (IR::Production production) -> inline_variant
    def empty_inline_variant(production)
      {
        rhs: [],
        steps: [],
        logical_refs: [],
        output_ref: nil,
        inline_used: false,
        inline_rule: nil,
        precedence_override: nil,
        precedence_contributes: false,
        parameter: production.expansion&.dig(:parameter)
      }
    end

    # @rbs (inline_variant variant, Integer symbol_id) -> inline_variant
    def append_inline_symbol(variant, symbol_id)
      # @type self: Normalizer
      rhs = variant.fetch(:rhs)
      terminal = @symbols.fetch(symbol_id).terminal?
      reference = [:physical, rhs.length] #: inline_reference
      logical_refs = variant.fetch(:logical_refs) + [reference] #: Array[inline_reference]
      result = variant.merge(
        rhs: rhs + [symbol_id],
        logical_refs: logical_refs,
        precedence_override: terminal ? nil : variant[:precedence_override],
        precedence_contributes: terminal || variant.fetch(:precedence_contributes)
      )
      result #: inline_variant
    end

    # @rbs (inline_variant parent, inline_variant child) -> inline_variant
    def combine_inline_variant(parent, child)
      physical_offset = parent.fetch(:rhs).length
      step_offset = parent.fetch(:steps).length
      steps = combined_inline_steps(parent, child, physical_offset, step_offset)
      output_ref = child.fetch(:output_ref) || raise(Ibex::Error, "inline choice has no output reference")
      rhs = append_inline_array(parent.fetch(:rhs), child.fetch(:rhs)) #: Array[Integer]
      combined_steps = append_inline_array(parent.fetch(:steps), steps) #: Array[inline_step]
      logical_refs = parent.fetch(:logical_refs) + [
        remap_inline_reference(output_ref, physical_offset, step_offset)
      ] #: Array[inline_reference]
      result = parent.merge(
        rhs: rhs,
        steps: combined_steps,
        logical_refs: logical_refs,
        inline_used: true,
        inline_rule: parent[:inline_rule] || child[:inline_rule],
        precedence_override: combined_inline_precedence(parent, child),
        precedence_contributes: parent.fetch(:precedence_contributes) ||
          child.fetch(:precedence_contributes),
        parameter: parent[:parameter] || child[:parameter]
      )
      result #: inline_variant
    end

    # @rbs (inline_variant parent, inline_variant child,
    #   Integer physical_offset, Integer step_offset) -> Array[inline_step]
    def combined_inline_steps(parent, child, physical_offset, step_offset)
      return child.fetch(:steps) if physical_offset.zero? && step_offset.zero? && parent.fetch(:logical_refs).empty?

      remap_inline_steps(parent, child, physical_offset, step_offset)
    end

    # The helper is shared by homogeneous integer and step arrays; callers
    # assert the concrete element type at each use site.
    # @rbs (Array[Object?] left, Array[Object?] right) -> Array[Object?]
    def append_inline_array(left, right)
      left.empty? ? right : left + right
    end

    # @rbs (inline_variant parent, inline_variant child) -> Integer?
    def combined_inline_precedence(parent, child)
      return child[:precedence_override] if child.fetch(:precedence_contributes)

      parent[:precedence_override]
    end

    # @rbs (inline_variant parent, inline_variant child,
    #   Integer physical_offset, Integer step_offset) -> Array[inline_step]
    def remap_inline_steps(parent, child, physical_offset, step_offset)
      child.fetch(:steps).map do |step|
        inputs = step.fetch(:inputs).map do |reference|
          remap_inline_reference(reference, physical_offset, step_offset)
        end
        stack_inputs = step.fetch(:stack_inputs).map do |reference|
          remap_inline_reference(reference, physical_offset, step_offset)
        end
        remapped = step.merge(
          inputs: inputs,
          stack_inputs: parent.fetch(:logical_refs) + stack_inputs,
          lookahead: step.fetch(:lookahead) + physical_offset
        )
        remapped #: inline_step
      end
    end

    # @rbs (Array[Symbol | Integer] reference, Integer physical_offset, Integer step_offset) ->
    #   Array[Symbol | Integer]
    def remap_inline_reference(reference, physical_offset, step_offset)
      kind, index = reference
      raise Ibex::Error, "invalid inline slot kind" unless kind.is_a?(Symbol)
      raise Ibex::Error, "invalid inline slot reference" unless index.is_a?(Integer)

      [kind, index + (kind == :physical ? physical_offset : step_offset)]
    end

    # @rbs (inline_variant variant, IR::Production production) -> inline_variant
    def finish_inline_precedence(variant, production)
      explicit = production.precedence_override
      variant.merge(
        precedence_override: explicit || variant[:precedence_override],
        precedence_contributes: !explicit.nil? || variant.fetch(:precedence_contributes)
      ) #: inline_variant
    end

    # @rbs (inline_variant variant, IR::Production production, Integer symbol_id) -> inline_variant
    def finish_inline_choice(variant, production, symbol_id)
      steps = variant.fetch(:steps)
      rule = @inline_rule_by_symbol.fetch(symbol_id)
      step = inline_action_step(production, variant.fetch(:logical_refs), variant.fetch(:rhs).length, :inline, rule)
      steps << step
      result = variant.merge(
        steps: steps,
        output_ref: [:step, steps.length - 1],
        inline_used: true,
        inline_rule: rule
      )
      result #: inline_variant
    end

    # @rbs (IR::Production production, Array[inline_reference] inputs, Integer lookahead,
    #   :inline | :rule kind, String? rule) -> inline_step
    def inline_action_step(production, inputs, lookahead, kind, rule)
      action = production.action
      {
        kind: kind,
        rule: rule,
        code: action&.code,
        loc: action&.location || production.origin.fetch(:loc),
        named_refs: action&.named_refs || [],
        context_length: action&.context_length || 0,
        inputs: inputs,
        stack_inputs: [],
        lookahead: lookahead,
        result_var: @options.fetch(:result_var),
        result_type: @symbols.fetch(production.lhs).semantic_type
      }
    end

    # @rbs (IR::Production production, inline_variant variant, Integer id) -> IR::Production
    def composed_inline_production(production, variant, id)
      steps = variant.fetch(:steps)
      caller = inline_action_step(
        production, variant.fetch(:logical_refs), variant.fetch(:rhs).length, :rule, nil
      )
      all_steps = steps + [caller]
      action = composed_inline_action(production, variant.fetch(:rhs).length, all_steps)
      IR::Production.new(
        id: id, lhs: production.lhs, rhs: variant.fetch(:rhs), action: action,
        precedence_override: variant[:precedence_override], origin: production.origin,
        documentation: production.documentation,
        expansion: inline_production_expansion(production, variant)
      )
    end

    # @rbs (IR::Production production, Integer physical_length, Array[inline_step]) -> IR::Action
    def composed_inline_action(production, physical_length, steps)
      action = production.action
      fragments = steps.map do |step|
        { kind: step.fetch(:kind), source: inline_source_provenance(step.fetch(:loc)) }
      end
      plan_steps = steps.map { |step| composition_plan_step(step, physical_length) }
      composition = {
        strategy: "sequence",
        fragments: fragments,
        plan: { version: 1, physical: physical_length, steps: plan_steps }
      } #: IR::action_composition
      IR::Action.new(
        code: action&.code || inline_implicit_code(production.rhs.length),
        location: action&.location || production.origin.fetch(:loc),
        composition: composition
      )
    end

    # @rbs (inline_step step, Integer physical_length) -> IR::action_composition_step
    def composition_plan_step(step, physical_length)
      {
        kind: step.fetch(:kind),
        rule: step[:rule],
        code: step[:code],
        loc: step.fetch(:loc),
        named_refs: step.fetch(:named_refs),
        context_length: step.fetch(:context_length),
        inputs: step.fetch(:inputs).map { |reference| resolve_inline_reference(reference, physical_length) },
        stack_inputs: step.fetch(:stack_inputs).map do |reference|
          resolve_inline_reference(reference, physical_length)
        end,
        lookahead: step.fetch(:lookahead) < physical_length ? step.fetch(:lookahead) : nil,
        result_var: step.fetch(:result_var),
        result_type: step[:result_type]
      }
    end

    # @rbs (Array[Symbol | Integer] reference, Integer physical_length) -> Integer
    def resolve_inline_reference(reference, physical_length)
      kind, index = reference
      raise Ibex::Error, "invalid inline slot reference" unless index.is_a?(Integer)

      index + (kind == :step ? physical_length : 0)
    end

    # @rbs (Integer rhs_length) -> String
    def inline_implicit_code(rhs_length)
      expression = rhs_length.zero? ? "nil" : "val[0]"
      @options.fetch(:result_var) ? " result = #{expression} " : " #{expression} "
    end

    # @rbs (IR::location location) -> IR::source_provenance
    def inline_source_provenance(location)
      { file: location[:file], root: @resolution&.root_directory, byte_span: nil }
    end

    # @rbs (IR::Production production, inline_variant variant) -> IR::production_expansion
    def inline_production_expansion(production, variant)
      existing = production.expansion
      inline_rule = variant.fetch(:inline_rule) || raise(Ibex::Error, "inline expansion has no rule")
      {
        parameter: existing&.dig(:parameter) || variant[:parameter],
        inline: { rule: inline_rule },
        include_chain: existing&.dig(:include_chain) || []
      }
    end

    # @rbs (IR::Production production, Integer id) -> IR::Production
    def copy_inline_production(production, id)
      IR::Production.new(
        id: id, lhs: production.lhs, rhs: production.rhs, action: production.action,
        precedence_override: production.precedence_override, origin: production.origin,
        documentation: production.documentation, expansion: production.expansion
      )
    end

    # @rbs (IR::Production production) -> void
    def charge_inline_expansion!(production)
      @inline_expansion_count += 1
      enforce_inline_choice_limit!(@inline_expansion_count, production.origin[:loc])
    end

    # @rbs (Integer count, IR::location? location) -> void
    def enforce_inline_choice_limit!(count, location)
      # @type self: Normalizer
      return if count <= @max_inline_expansions

      fail_hash(location, "inline expansion limit of #{@max_inline_expansions} exceeded")
    end

    # @rbs (Array[IR::Production] productions) -> void
    def rebuild_inline_symbols(productions)
      kept = @symbols.reject { |definition| @inline_symbol_ids.include?(definition.id) }
      id_map = kept.each_with_index.to_h { |definition, id| [definition.id, id] }
      @symbols = kept.each_with_index.map { |definition, id| remap_inline_symbol(definition, id) }
      @symbols_by_name = @symbols.to_h { |definition| [definition.name, definition] }
      @productions = productions.each_with_index.map do |production, id|
        remap_inline_production(production, id, id_map)
      end
    end

    # @rbs (IR::GrammarSymbol definition, Integer id) -> IR::GrammarSymbol
    def remap_inline_symbol(definition, id)
      IR::GrammarSymbol.new(
        id: id, name: definition.name, kind: definition.kind, reserved: definition.reserved,
        precedence: definition.precedence, location: definition.location,
        display_name: definition.display_name, semantic_type: definition.semantic_type,
        documentation: definition.documentation
      )
    end

    # @rbs (IR::Production production, Integer id, Hash[Integer, Integer] id_map) -> IR::Production
    def remap_inline_production(production, id, id_map)
      IR::Production.new(
        id: id, lhs: id_map.fetch(production.lhs),
        rhs: production.rhs.map { |symbol_id| id_map.fetch(symbol_id) },
        action: production.action,
        precedence_override: production.precedence_override && id_map.fetch(production.precedence_override),
        origin: production.origin, documentation: production.documentation, expansion: production.expansion
      )
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
