# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Impact
    # Checks only structured action metadata; action source remains opaque.
    class ActionImpact
      attr_reader :findings #: Array[Hash[Symbol, Object?]]

      # @rbs (IR::Grammar before, IR::Grammar after, ?affected_names: Array[String]?) -> void
      def initialize(before, after, affected_names: nil)
        @before = before
        @after = after
        @affected_names = affected_names
        @findings = compare
        freeze
      end

      # @rbs () -> Array[Hash[Symbol, Object?]]
      def to_a
        @findings
      end

      private

      # @rbs () -> Array[Hash[Symbol, Object?]]
      def compare
        names = @after.nonterminals.map(&:name)
        names &= @affected_names if @affected_names
        names.sort.flat_map { |name| compare_rule(name) }.sort_by { |finding| finding.fetch(:production) }
      end

      # @rbs (String name) -> Array[Hash[Symbol, Object?]]
      def compare_rule(name)
        before = productions_for(@before, name)
        after = productions_for(@after, name)
        after.each_with_index.filter_map do |production, index|
          previous = before[index]
          next unless previous
          next if previous.rhs.length == production.rhs.length

          finding_for(previous, production)
        end
      end

      # @rbs (IR::Grammar grammar, String name) -> Array[IR::Production]
      def productions_for(grammar, name)
        lhs = grammar.symbol(name)&.id
        return [] unless lhs

        grammar.productions.select { |production| production.lhs == lhs }
      end

      # @rbs (IR::Production before, IR::Production after) -> Hash[Symbol, Object?]
      def finding_for(before, after)
        action = after.action
        reason, severity = finding_reason(action, before.rhs.length, after.rhs.length)
        {
          production: production_name(@after, after), severity: severity,
          reason: reason,
          context_length: { before: before.rhs.length, after: after.rhs.length },
          loc: after.action&.location || after.origin[:loc]
        }
      end

      # @rbs (IR::Action?, Integer, Integer) -> [String, String]
      def finding_reason(action, before_length, after_length)
        return %w[named_ref_index_out_of_range high] if out_of_range?(action, after_length)
        return %w[context_length_stale high] if action&.context_length == before_length

        %w[rhs_length_changed medium]
      end

      # @rbs (IR::Action?, Integer) -> bool
      def out_of_range?(action, length)
        action&.named_refs&.any? { |reference| reference.fetch(:index) >= length } || false
      end

      # @rbs (IR::Grammar grammar, IR::Production production) -> String
      def production_name(grammar, production)
        lhs = grammar.symbol_by_id(production.lhs)&.name || production.lhs.to_s
        rhs = production.rhs.map { |id| grammar.symbol_by_id(id)&.name || id.to_s }
        "#{lhs} -> #{rhs.join(' ')}"
      end
    end
  end
end
