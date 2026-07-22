# frozen_string_literal: true

module Ibex
  module Codegen
    # Renders a self-contained navigable automaton report.
    module HTML
      # @rbs!
      #   private def state_sections: (IR::Automaton automaton, IR::Grammar grammar) -> String
      #   private def self.state_sections: (IR::Automaton automaton, IR::Grammar grammar) -> String
      #   private def item_html: (IR::AutomatonItem item, IR::Grammar grammar) -> String
      #   private def self.item_html: (IR::AutomatonItem item, IR::Grammar grammar) -> String
      #   private def rule_sections: (IR::Grammar grammar) -> String
      #   private def self.rule_sections: (IR::Grammar grammar) -> String
      #   private def conflict_sections: (IR::Automaton automaton) -> String
      #   private def self.conflict_sections: (IR::Automaton automaton) -> String
      #   private def escape: (String value) -> String
      #   private def self.escape: (String value) -> String
      #   private def symbol_name: (IR::Grammar grammar, Integer id) -> String
      #   private def self.symbol_name: (IR::Grammar grammar, Integer id) -> String

      # @rbs (IR::Automaton automaton) -> String
      def render(automaton)
        grammar = automaton.grammar
        <<~HTML
          <!doctype html>
          <html lang="en"><head><meta charset="utf-8"><title>Ibex automaton</title>
          <style>body{font:14px system-ui;margin:2rem;max-width:90rem}code{white-space:pre-wrap}.state{border:1px solid #bbb;padding:1rem;margin:1rem 0}.conflict{color:#a00}a{color:#075985}</style>
          </head><body><h1>Ibex #{escape(automaton.algorithm)} automaton</h1>
          <nav><a href="#rules">Rules</a> · <a href="#conflicts">Conflicts</a></nav>
          #{state_sections(automaton, grammar)}
          <h2 id="rules">Rules</h2>#{rule_sections(grammar)}
          <h2 id="conflicts">Conflicts</h2>#{conflict_sections(automaton)}
          </body></html>
        HTML
      end
      module_function :render

      # @rbs skip
      private

      # @rbs skip
      def state_sections(automaton, grammar)
        automaton.states.map do |state|
          transitions = state.transitions.map do |symbol_id, target|
            symbol = escape(symbol_name(grammar, symbol_id))
            "<li>#{symbol} → <a href=\"#state-#{target}\">state #{target}</a></li>"
          end.join
          items = state.items.map { |item| item_html(item, grammar) }.join
          <<~HTML
            <section class="state" id="state-#{state.id}"><h2>State #{state.id}</h2>
            <ul>#{transitions}</ul><ul>#{items}</ul></section>
          HTML
        end.join
      end

      # @rbs skip
      def item_html(item, grammar)
        return "<li><code>$accept</code></li>" if item.production.negative?

        production = grammar.productions.fetch(item.production)
        lhs = symbol_name(grammar, production.lhs)
        rhs = production.rhs.map { |id| symbol_name(grammar, id) }.insert(item.dot, "•").join(" ")
        link = "<a href=\"#rule-#{production.id}\">rule #{production.id}</a>"
        "<li>#{link} <code>#{escape(lhs)} → #{escape(rhs)}</code></li>"
      end

      # @rbs skip
      def rule_sections(grammar)
        grammar.productions.map do |production|
          lhs = symbol_name(grammar, production.lhs)
          rhs = production.rhs.map { |id| symbol_name(grammar, id) }.join(" ")
          number = "<strong>#{production.id}</strong>"
          "<p id=\"rule-#{production.id}\">#{number} <code>#{escape(lhs)} → #{escape(rhs)}</code></p>"
        end.join
      end

      # @rbs skip
      def conflict_sections(automaton)
        conflicts = automaton.states.flat_map do |state|
          state.conflicts.map do |conflict|
            link = "<a href=\"#state-#{state.id}\">state #{state.id}</a>"
            "<li class=\"conflict\">#{link}: #{escape(conflict.inspect)}</li>"
          end
        end
        conflicts.empty? ? "<p>None</p>" : "<ul>#{conflicts.join}</ul>"
      end

      # @rbs skip
      def escape(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end

      # @rbs skip
      def symbol_name(grammar, id)
        symbol = grammar.symbol_by_id(id) || raise(Ibex::Error, "missing grammar symbol id #{id}")
        symbol.name
      end
      module_function :state_sections, :item_html, :rule_sections, :conflict_sections, :escape, :symbol_name

      class << self
        private :state_sections, :item_html, :rule_sections, :conflict_sections, :escape, :symbol_name
      end
    end
  end
end
