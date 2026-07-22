# frozen_string_literal: true

module Ibex
  module Codegen
    # Builds human-facing symbol labels without changing Grammar IR identities.
    module SymbolLabels
      # @rbs (IR::Grammar grammar) -> Hash[Integer, String]
      def self.build(grammar)
        labels = grammar.symbols.to_h { |symbol| [symbol.id, symbol.name] }
        grammar.productions.each do |production|
          expression = production.origin[:expression]
          labels[production.lhs] = expression if expression.is_a?(String)
        end
        labels
      end
    end
  end
end
