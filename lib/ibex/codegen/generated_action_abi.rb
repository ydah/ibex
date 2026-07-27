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
    end
  end
end
