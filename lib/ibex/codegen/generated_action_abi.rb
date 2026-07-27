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

      # Keeps semantic-action analysis local to one code-generation run.
      class Cache
        # @rbs @values_only: Hash[Integer, bool]
        # @rbs @borrowed_values: Hash[Integer, bool]
        # @rbs @positional_actions: Hash[Integer, String?]

        # @rbs () -> void
        def initialize
          @values_only = {}
          @borrowed_values = {}
          @positional_actions = {}
        end

        # @rbs (IR::Production production) -> bool
        def values_only?(production)
          @values_only.fetch(production.id) do
            @values_only[production.id] = GeneratedActionABI.values_only?(production)
          end
        end

        # @rbs (IR::Production production) -> bool
        def borrowed_values?(production)
          @borrowed_values.fetch(production.id) do
            @borrowed_values[production.id] =
              GeneratedActionABI.borrowed_values?(production, analysis: self)
          end
        end

        # @rbs (IR::Production production) -> String?
        def positional_action_source(production)
          @positional_actions.fetch(production.id) do
            @positional_actions[production.id] =
              GeneratedActionABI.positional_action_source(production, analysis: self)
          end
        end

        # @rbs (IR::Production production) -> bool
        def positional_values?(production)
          !positional_action_source(production).nil?
        end
      end

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
      # @rbs (IR::Production production, ?analysis: singleton(GeneratedActionABI) | Cache) -> bool
      def borrowed_values?(production, analysis: self)
        return false unless analysis.values_only?(production)

        action = production.action
        return false unless action

        maximum = production.rhs.length
        source = ActionLocations.new(action.code, maximum: maximum, location: action.location).rewrite
        return true if simple_indexed_values_action?(source)

        require "ripper"
        syntax = Object.const_get(:Ripper).__send__(:sexp, source)
        !syntax.nil? && read_only_value_references?(syntax)
      end

      # Return semantic source rewritten for zero-to-four positional RHS
      # arguments, or nil when the values container remains observable.
      # @rbs (IR::Production production, ?analysis: singleton(GeneratedActionABI) | Cache) -> String?
      def positional_action_source(production, analysis: self)
        return nil unless analysis.values_only?(production)
        return nil unless production.rhs.length <= 4

        action = production.action
        return "" unless action
        return nil unless analysis.borrowed_values?(production)

        parameters = Array.new(production.rhs.length) { |index| "v#{index}" }
        return nil if action.named_refs.any? { |reference| parameters.include?(reference[:name]) }

        maximum = production.rhs.length
        source = ActionLocations.new(action.code, maximum: maximum, location: action.location).rewrite
        simple = simple_positional_action_source(source, parameters)
        return simple unless simple.nil?

        require "ripper"
        tokens = Object.const_get(:Ripper).__send__(:lex, source)
        return nil unless tokens.map { |_position, _event, token, _state| token }.join == source

        rewrite_positional_values(tokens, parameters)
      end

      # @rbs (IR::Production production) -> bool
      def positional_values?(production)
        !positional_action_source(production).nil?
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

      # Keep the most common identity action off the Ripper load path. The
      # whole-source match excludes strings, comments, receivers, and compound
      # expressions before replacing the one direct read.
      # @rbs (String source, Array[String] parameters) -> String?
      def simple_positional_action_source(source, parameters)
        match = /\A\s*(?:result\s*=\s*)?val\[\s*(\d+)\s*\]\s*\z/.match(source)
        return nil unless match

        parameter = parameters[Integer(match[1] || "", 10)]
        source.sub(/\bval\[\s*\d+\s*\]/, parameter) if parameter
      end
      private_class_method :simple_positional_action_source

      # @rbs (Array[untyped] tokens, Array[String] parameters) -> String?
      def rewrite_positional_values(tokens, parameters)
        result = [] #: Array[String]
        index = 0
        while index < tokens.length
          _position, event, token, _state = tokens[index]
          return nil if event == :on_ident && parameters.include?(token)

          unless event == :on_ident && token == "val"
            result << token
            index += 1
            next
          end

          reference = positional_value_reference(tokens, index, parameters)
          return nil unless reference

          result << reference.fetch(0)
          index = reference.fetch(1)
        end
        result.join
      end
      private_class_method :rewrite_positional_values

      # @rbs (Array[untyped] tokens, Integer index, Array[String] parameters) -> [String, Integer]?
      def positional_value_reference(tokens, index, parameters)
        previous_event = index.zero? ? nil : tokens[index - 1][1]
        return nil if %i[on_period on_op].include?(previous_event)

        reference = tokens.slice(index + 1, 3)
        return nil unless reference
        return nil unless reference.map { |entry| entry[1] } == %i[on_lbracket on_int on_rbracket]

        parameter = parameters[Integer(reference.fetch(1).fetch(2), 10)]
        [parameter, index + 4] if parameter
      rescue ArgumentError
        nil
      end
      private_class_method :positional_value_reference

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
