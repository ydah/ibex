# frozen_string_literal: true

require_relative "symbol_labels"

module Ibex
  module Codegen
    # Renders an Automaton IR graph as a GitHub-compatible Mermaid flowchart.
    module Mermaid
      # @rbs (IR::Automaton automaton) -> String
      def render(automaton)
        labels = SymbolLabels.build(automaton.grammar)
        lines = ["flowchart LR"]
        automaton.states.each do |state|
          lines << %(  state_#{state.id}["State #{state.id}"])
          state.transitions.each do |symbol_id, target|
            label = escape(labels.fetch(symbol_id) { raise Ibex::Error, "missing grammar symbol id #{symbol_id}" })
            lines << "  state_#{state.id} -->|#{label}| state_#{target}"
          end
        end
        conflicting = automaton.states.reject { |state| state.conflicts.empty? }
        unless conflicting.empty?
          lines << "  classDef conflict fill:#fee2e2,stroke:#b91c1c,stroke-width:2px"
          conflicting.each { |state| lines << "  class state_#{state.id} conflict;" }
        end
        "#{lines.join("\n")}\n"
      end
      module_function :render

      private

      # @rbs (String value) -> String
      def escape(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("|", "&#124;")
             .gsub('"', "&quot;").gsub(/\s+/, " ")
      end
      module_function :escape

      class << self
        private :escape
      end
    end
  end
end
