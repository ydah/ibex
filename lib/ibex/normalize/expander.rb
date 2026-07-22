# frozen_string_literal: true

module Ibex
  # Production and EBNF expansion used by Normalizer.
  module NormalizeExpander
    private

    # @rbs () -> void
    def normalize_user_productions
      # @type self: Normalizer
      @ast.rules.each do |rule|
        rule.alternatives.each { |alternative| normalize_alternative(rule, alternative) }
      end
    end

    # @rbs (Frontend::AST::Rule rule, Frontend::AST::Alternative alternative) -> void
    def normalize_alternative(rule, alternative)
      # @type self: Normalizer
      rhs = [] #: Array[String]
      named_refs = [] #: Array[IR::named_ref]
      alternative.items.each do |item|
        if item.is_a?(Frontend::AST::InlineAction)
          rhs << expand_inline_action(item, rhs.length, named_refs)
          next
        end

        rhs << normalize_item(item)
        add_named_reference(item, named_refs, rhs.length - 1)
      end
      action = normalize_action(alternative.action, named_refs)
      add_production(rule.lhs, rhs, action, alternative.precedence,
                     { kind: :user, loc: alternative.loc.to_h })
    end

    # @rbs (Frontend::AST::item item) -> String
    def normalize_item(item)
      # @type self: Normalizer
      return symbol_for_reference(item).name if item.is_a?(Frontend::AST::SymbolReference)
      return expand_group(item) if item.is_a?(Frontend::AST::Group)
      return expand_optional(item) if item.is_a?(Frontend::AST::Optional)
      return expand_star(item) if item.is_a?(Frontend::AST::Star)
      return expand_plus(item) if item.is_a?(Frontend::AST::Plus)
      return expand_separated_list(item) if item.is_a?(Frontend::AST::SeparatedList)

      fail_at(item.loc, "unsupported nested EBNF expression")
    end

    # @rbs (Frontend::AST::InlineAction item, Integer context_length, Array[IR::named_ref] named_refs) -> String
    def expand_inline_action(item, context_length, named_refs)
      # @type self: Normalizer
      helper = new_helper("inline", item.loc)
      action = IR::Action.new(code: item.code, location: item.loc.to_h, named_refs: named_refs.map(&:dup),
                              context_length: context_length)
      add_production(helper, [], action, nil, { kind: :inline_action, loc: item.loc.to_h })
      helper
    end

    # @rbs (Frontend::AST::Optional item) -> String
    def expand_optional(item)
      # @type self: Normalizer
      base = normalize_item(item.item)
      helper = new_helper("optional", item.loc)
      add_production(helper, [], synthetic_action("nil", item.loc), nil, synthetic_origin(:optional, item))
      add_production(helper, [base], synthetic_action("val[0]", item.loc), nil, synthetic_origin(:optional, item))
      helper
    end

    # @rbs (Frontend::AST::Star item) -> String
    def expand_star(item)
      # @type self: Normalizer
      base = normalize_item(item.item)
      helper = new_helper("star", item.loc)
      add_production(helper, [], synthetic_action("[]", item.loc), nil, synthetic_origin(:star, item))
      add_production(helper, [helper, base], synthetic_action("val[0] + [val[1]]", item.loc), nil,
                     synthetic_origin(:star, item))
      helper
    end

    # @rbs (Frontend::AST::Plus item) -> String
    def expand_plus(item)
      # @type self: Normalizer
      base = normalize_item(item.item)
      helper = new_helper("plus", item.loc)
      add_production(helper, [base], synthetic_action("[val[0]]", item.loc), nil, synthetic_origin(:plus, item))
      add_production(helper, [helper, base], synthetic_action("val[0] + [val[1]]", item.loc), nil,
                     synthetic_origin(:plus, item))
      helper
    end

    # @rbs (Frontend::AST::SeparatedList item) -> String
    def expand_separated_list(item)
      # @type self: Normalizer
      base = normalize_item(item.item)
      separator = normalize_item(item.separator)
      helper = new_helper("separated_list", item.loc)
      unless item.nonempty
        add_production(helper, [], synthetic_action("[]", item.loc), nil, synthetic_origin(:separated_list, item))
      end
      add_production(helper, [base], synthetic_action("[val[0]]", item.loc), nil,
                     synthetic_origin(:separated_list, item))
      add_production(helper, [helper, separator, base], synthetic_action("val[0] + [val[2]]", item.loc), nil,
                     synthetic_origin(:separated_list, item))
      helper
    end

    # @rbs (Frontend::AST::Group item) -> String
    def expand_group(item)
      # @type self: Normalizer
      reject_group_named_references(item)
      helper = new_helper("group", item.loc)
      item.alternatives.each do |alternative|
        rhs = alternative.map { |child| normalize_item(child) }
        expression = group_value_expression(rhs.length)
        add_production(helper, rhs, synthetic_action(expression, item.loc), nil, synthetic_origin(:group, item))
      end
      helper
    end

    # @rbs (Integer length) -> String
    def group_value_expression(length)
      # @type self: Normalizer
      return "nil" if length.zero?
      return "val[0]" if length == 1

      "val"
    end

    # @rbs (Frontend::AST::Group group) -> void
    def reject_group_named_references(group)
      # @type self: Normalizer
      reference = group.alternatives.flatten.filter_map { |item| named_reference_in(item) }.first
      fail_at(reference.loc, "named references inside EBNF groups are not supported") if reference
    end

    # @rbs (Frontend::AST::item item) -> Frontend::AST::SymbolReference?
    def named_reference_in(item)
      # @type self: Normalizer
      return item if item.is_a?(Frontend::AST::SymbolReference) && item.named_reference
      if item.is_a?(Frontend::AST::Group)
        return item.alternatives.flatten.filter_map { |child| named_reference_in(child) }.first
      end
      if item.is_a?(Frontend::AST::Optional) || item.is_a?(Frontend::AST::Star) ||
         item.is_a?(Frontend::AST::Plus) || item.is_a?(Frontend::AST::SeparatedList)
        return named_reference_in(item.item)
      end

      nil
    end

    # @rbs (String kind, Frontend::Location location) -> String
    def new_helper(kind, location)
      # @type self: Normalizer
      @helper_sequence += 1
      name = "$#{kind}_#{@helper_sequence}"
      intern(name, :nonterminal, location: location.to_h)
      name
    end

    # @rbs (String expression, Frontend::Location location) -> IR::Action
    def synthetic_action(expression, location)
      # @type self: Normalizer
      code = @options[:result_var] ? " result = #{expression} " : " #{expression} "
      IR::Action.new(code: code, location: location.to_h)
    end

    # @rbs (Symbol kind, Frontend::AST::item item) -> Hash[Symbol, untyped]
    def synthetic_origin(kind, item)
      # @type self: Normalizer
      { kind: :"#{kind}_expansion", loc: item.loc.to_h }
    end

    # @rbs (Frontend::AST::InlineAction? action, Array[IR::named_ref] named_refs) -> IR::Action?
    def normalize_action(action, named_refs)
      # @type self: Normalizer
      return nil unless action

      IR::Action.new(code: action.code, location: action.loc.to_h, named_refs: named_refs)
    end

    # @rbs (Frontend::AST::item item, Array[IR::named_ref] refs, Integer index) -> void
    def add_named_reference(item, refs, index)
      # @type self: Normalizer
      reference = unwrap_reference(item)
      return unless reference

      name = reference.named_reference
      return unless name

      fail_at(reference.loc, "reserved named reference #{name}") if Normalizer::RESERVED_NAMES.include?(name)
      fail_at(reference.loc, "duplicate named reference #{name}") if refs.any? { |entry| entry[:name] == name }
      refs << { name: name, index: index }
    end

    # @rbs (Frontend::AST::item item) -> Frontend::AST::SymbolReference?
    def unwrap_reference(item)
      # @type self: Normalizer
      return item if item.is_a?(Frontend::AST::SymbolReference)
      if item.is_a?(Frontend::AST::Optional) || item.is_a?(Frontend::AST::Star) ||
         item.is_a?(Frontend::AST::Plus) || item.is_a?(Frontend::AST::SeparatedList)
        return unwrap_reference(item.item)
      end

      nil
    end

    # @rbs (String lhs_name, Array[String] rhs_names, IR::Action? action, String? precedence_name,
    #   Hash[Symbol, untyped] origin) -> void
    def add_production(lhs_name, rhs_names, action, precedence_name, origin)
      # @type self: Normalizer
      lhs = symbol(lhs_name) || intern(lhs_name, :nonterminal, location: origin[:loc])
      rhs = rhs_names.map { |name| symbol(name)&.id || fail_hash(origin[:loc], "undefined symbol #{name}") }
      precedence = precedence_name && symbol(precedence_name)
      fail_hash(origin[:loc], "undefined precedence symbol #{precedence_name}") if precedence_name && !precedence
      @productions << IR::Production.new(id: @productions.length, lhs: lhs.id, rhs: rhs, action: action,
                                         precedence_override: precedence&.id, origin: origin)
    end
  end
end
