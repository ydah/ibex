# frozen_string_literal: true

module Ibex
  module Codegen
    # Renders Graphviz DOT from Automaton IR.
    module Dot
      module_function

      def render(automaton)
        lines = ["digraph ibex_automaton {", "  rankdir=LR;", "  node [shape=box];"]
        automaton.states.each do |state|
          attributes = ["label=\"State #{state.id}\""]
          attributes << "color=red" unless state.conflicts.empty?
          lines << "  state_#{state.id} [#{attributes.join(', ')}];"
          state.transitions.each do |symbol_id, target|
            label = escape(automaton.grammar.symbol_by_id(symbol_id).name)
            lines << "  state_#{state.id} -> state_#{target} [label=\"#{label}\"];"
          end
        end
        lines << "}"
        "#{lines.join("\n")}\n"
      end

      def escape(value)
        value.gsub("\\", "\\\\").gsub('"', '\\"')
      end
      private_class_method :escape
    end
  end
end
