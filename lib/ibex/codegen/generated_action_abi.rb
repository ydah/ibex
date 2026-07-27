# frozen_string_literal: true
# rbs_inline: enabled

require_relative "action_locations"

module Ibex
  module Codegen
    # Selects the smallest generated semantic-action ABI that preserves the
    # action's declared inputs.
    module GeneratedActionABI
      LEGACY_PARAMETERS = %w[
        _values
        _ibex_locations
        _ibex_location_stack
        _ibex_location
        _ibex_lookahead_location
      ].freeze #: Array[String]
      private_constant :LEGACY_PARAMETERS

      module_function

      # @rbs (IR::Production production) -> bool
      def values_only?(production)
        return false if production.action&.composition

        action = production.action
        return true unless action
        return false if action.context_length.positive?

        maximum = production.rhs.length
        locations = ActionLocations.new(action.code, maximum: maximum, location: action.location)
        !locations.references? && !references_legacy_parameter?(action.code)
      end

      # The direct runtime can share one reduction-values array with an action
      # and a hook installed by that action only when the action cannot mutate
      # or retain the array itself. Element reads and parallel assignment copy
      # values out without exposing the container.
      # @rbs (IR::Production production) -> bool
      def borrowed_values?(production)
        return false unless values_only?(production)

        action = production.action
        return false unless action

        maximum = production.rhs.length
        source = ActionLocations.new(action.code, maximum: maximum, location: action.location).rewrite
        return true if simple_indexed_values_action?(source)

        require "ripper"
        syntax = Object.const_get(:Ripper).__send__(:sexp, source)
        !syntax.nil? && read_only_value_references?(syntax)
      end

      # Avoid loading a Ruby parser for the overwhelmingly common generated
      # action shape. This accepts only a single result assignment (or a bare
      # expression), simple numeric val reads, and no further assignment.
      # Anything less obvious falls back to Ripper below.
      # @rbs (String source) -> bool
      def simple_indexed_values_action?(source)
        body = source.strip
        assignment = /\Aresult\s*=\s*(.*)\z/m.match(body)
        body = (assignment[1] || "").strip if assignment
        return false if body.empty? || body.match?(/(?<![=!<>])=(?!=|>)/)

        without_reads = body.gsub(/\bval\[\s*\d+\s*\]/, "")
        without_reads != body && !without_reads.match?(/\bval\b/)
      end
      private_class_method :simple_indexed_values_action?

      # @rbs (String source) -> bool
      def references_legacy_parameter?(source)
        return false unless LEGACY_PARAMETERS.any? { |parameter| source.include?(parameter) }

        require "ripper"
        tokens = Object.const_get(:Ripper).__send__(:lex, source.gsub(/@(?:\$|\d+)/) { |match| "_" * match.bytesize })
        tokens.any? do |_position, type, token, _state|
          type == :on_ident && LEGACY_PARAMETERS.include?(token)
        end
      end
      private_class_method :references_legacy_parameter?

      # @rbs (untyped node, ?untyped parent, ?Integer? child_index) -> bool
      def read_only_value_references?(node, parent = nil, child_index = nil)
        return true unless node.is_a?(Array)
        return safe_value_reference?(parent, child_index) if value_reference?(node)

        node.each_with_index.all? do |child, index|
          read_only_value_references?(child, node, index)
        end
      end
      private_class_method :read_only_value_references?

      # @rbs (untyped node) -> bool
      def value_reference?(node)
        node[0] == :vcall && node.dig(1, 0) == :@ident && node.dig(1, 1) == "val"
      end
      private_class_method :value_reference?

      # @rbs (untyped parent, Integer? child_index) -> bool
      def safe_value_reference?(parent, child_index)
        return false unless parent.is_a?(Array)

        (parent[0] == :aref && child_index == 1) ||
          (parent[0] == :massign && child_index == 2)
      end
      private_class_method :safe_value_reference?
    end
  end
end
