# frozen_string_literal: true

module Ibex
  module Codegen
    # Renders Graphviz DOT from Automaton IR.
    module Dot
      # @rbs!
      #   private def escape: (String value) -> String
      #   private def self.escape: (String value) -> String
      #   private def symbol_name: (IR::Grammar grammar, Integer id) -> String
      #   private def self.symbol_name: (IR::Grammar grammar, Integer id) -> String

      # @rbs (IR::Automaton automaton) -> String
      def render(automaton)
        lines = ["digraph ibex_automaton {", "  rankdir=LR;", "  node [shape=box];"]
        automaton.states.each do |state|
          attributes = ["label=\"State #{state.id}\""]
          attributes << "color=red" unless state.conflicts.empty?
          lines << "  state_#{state.id} [#{attributes.join(', ')}];"
          state.transitions.each do |symbol_id, target|
            label = escape(symbol_name(automaton.grammar, symbol_id))
            lines << "  state_#{state.id} -> state_#{target} [label=\"#{label}\"];"
          end
        end
        lines << "}"
        "#{lines.join("\n")}\n"
      end
      module_function :render

      # @rbs skip
      private

      # @rbs skip
      def escape(value)
        value.gsub("\\", "\\\\").gsub('"', '\\"')
      end

      # @rbs skip
      def symbol_name(grammar, id)
        symbol = grammar.symbol_by_id(id) || raise(Ibex::Error, "missing grammar symbol id #{id}")
        symbol.name
      end
      module_function :escape, :symbol_name

      class << self
        private :escape, :symbol_name
      end
    end
  end
end
