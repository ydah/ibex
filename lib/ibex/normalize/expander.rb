# frozen_string_literal: true

module Ibex
  # Production and EBNF expansion used by Normalizer.
  module NormalizeExpander
    private

    def normalize_user_productions
      @ast.rules.each do |rule|
        rule.alternatives.each { |alternative| normalize_alternative(rule, alternative) }
      end
    end

    def normalize_alternative(rule, alternative)
      rhs = []
      named_refs = []
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

    def normalize_item(item)
      return symbol_for_reference(item).name if item.is_a?(Frontend::AST::SymbolReference)
      return expand_optional(item) if item.is_a?(Frontend::AST::Optional)
      return expand_star(item) if item.is_a?(Frontend::AST::Star)
      return expand_plus(item) if item.is_a?(Frontend::AST::Plus)
      return expand_separated_list(item) if item.is_a?(Frontend::AST::SeparatedList)

      fail_at(item.loc, "unsupported nested EBNF expression")
    end

    def expand_inline_action(item, context_length, named_refs)
      helper = new_helper("inline", item.loc)
      action = IR::Action.new(code: item.code, location: item.loc.to_h, named_refs: named_refs.map(&:dup),
                              context_length: context_length)
      add_production(helper, [], action, nil, { kind: :inline_action, loc: item.loc.to_h })
      helper
    end

    def expand_optional(item)
      base = simple_ebnf_item(item.item)
      helper = new_helper("optional", item.loc)
      add_production(helper, [], synthetic_action("nil", item.loc), nil, synthetic_origin(:optional, item))
      add_production(helper, [base], synthetic_action("val[0]", item.loc), nil, synthetic_origin(:optional, item))
      helper
    end

    def expand_star(item)
      base = simple_ebnf_item(item.item)
      helper = new_helper("star", item.loc)
      add_production(helper, [], synthetic_action("[]", item.loc), nil, synthetic_origin(:star, item))
      add_production(helper, [helper, base], synthetic_action("val[0] + [val[1]]", item.loc), nil,
                     synthetic_origin(:star, item))
      helper
    end

    def expand_plus(item)
      base = simple_ebnf_item(item.item)
      helper = new_helper("plus", item.loc)
      add_production(helper, [base], synthetic_action("[val[0]]", item.loc), nil, synthetic_origin(:plus, item))
      add_production(helper, [helper, base], synthetic_action("val[0] + [val[1]]", item.loc), nil,
                     synthetic_origin(:plus, item))
      helper
    end

    def expand_separated_list(item)
      base = simple_ebnf_item(item.item)
      separator = simple_ebnf_item(item.separator)
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

    def simple_ebnf_item(item)
      return symbol_for_reference(item).name if item.is_a?(Frontend::AST::SymbolReference)

      fail_at(item.loc, "nested EBNF expressions are not supported")
    end

    def new_helper(kind, location)
      @helper_sequence += 1
      name = "$#{kind}_#{@helper_sequence}"
      intern(name, :nonterminal, location: location.to_h)
      name
    end

    def synthetic_action(expression, location)
      code = @options[:result_var] ? " result = #{expression} " : " #{expression} "
      IR::Action.new(code: code, location: location.to_h)
    end

    def synthetic_origin(kind, item)
      { kind: :"#{kind}_expansion", loc: item.loc.to_h }
    end

    def normalize_action(action, named_refs)
      return nil unless action

      IR::Action.new(code: action.code, location: action.loc.to_h, named_refs: named_refs)
    end

    def add_named_reference(item, refs, index)
      reference = unwrap_reference(item)
      return unless reference&.named_reference

      name = reference.named_reference
      fail_at(reference.loc, "reserved named reference #{name}") if Normalizer::RESERVED_NAMES.include?(name)
      fail_at(reference.loc, "duplicate named reference #{name}") if refs.any? { |entry| entry[:name] == name }
      refs << { name: name, index: index }
    end

    def unwrap_reference(item)
      return item if item.is_a?(Frontend::AST::SymbolReference)
      return item.item if item.respond_to?(:item)

      nil
    end

    def add_production(lhs_name, rhs_names, action, precedence_name, origin)
      lhs = symbol(lhs_name) || intern(lhs_name, :nonterminal, location: origin[:loc])
      rhs = rhs_names.map { |name| symbol(name)&.id || fail_hash(origin[:loc], "undefined symbol #{name}") }
      precedence = precedence_name && symbol(precedence_name)
      fail_hash(origin[:loc], "undefined precedence symbol #{precedence_name}") if precedence_name && !precedence
      @productions << IR::Production.new(id: @productions.length, lhs: lhs.id, rhs: rhs, action: action,
                                         precedence_override: precedence&.id, origin: origin)
    end
  end
end
