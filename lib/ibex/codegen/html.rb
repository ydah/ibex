# frozen_string_literal: true

module Ibex
  module Codegen
    # Renders a self-contained navigable automaton report.
    module HTML
      module_function

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

      def state_sections(automaton, grammar)
        automaton.states.map do |state|
          transitions = state.transitions.map do |symbol_id, target|
            symbol = escape(grammar.symbol_by_id(symbol_id).name)
            "<li>#{symbol} → <a href=\"#state-#{target}\">state #{target}</a></li>"
          end.join
          items = state.items.map { |item| item_html(item, grammar) }.join
          <<~HTML
            <section class="state" id="state-#{state.id}"><h2>State #{state.id}</h2>
            <ul>#{transitions}</ul><ul>#{items}</ul></section>
          HTML
        end.join
      end
      private_class_method :state_sections

      def item_html(item, grammar)
        return "<li><code>$accept</code></li>" if item.production.negative?

        production = grammar.productions.fetch(item.production)
        lhs = grammar.symbol_by_id(production.lhs).name
        rhs = production.rhs.map { |id| grammar.symbol_by_id(id).name }.insert(item.dot, "•").join(" ")
        link = "<a href=\"#rule-#{production.id}\">rule #{production.id}</a>"
        "<li>#{link} <code>#{escape(lhs)} → #{escape(rhs)}</code></li>"
      end
      private_class_method :item_html

      def rule_sections(grammar)
        grammar.productions.map do |production|
          lhs = grammar.symbol_by_id(production.lhs).name
          rhs = production.rhs.map { |id| grammar.symbol_by_id(id).name }.join(" ")
          number = "<strong>#{production.id}</strong>"
          "<p id=\"rule-#{production.id}\">#{number} <code>#{escape(lhs)} → #{escape(rhs)}</code></p>"
        end.join
      end
      private_class_method :rule_sections

      def conflict_sections(automaton)
        conflicts = automaton.states.flat_map do |state|
          state.conflicts.map do |conflict|
            link = "<a href=\"#state-#{state.id}\">state #{state.id}</a>"
            "<li class=\"conflict\">#{link}: #{escape(conflict.inspect)}</li>"
          end
        end
        conflicts.empty? ? "<p>None</p>" : "<ul>#{conflicts.join}</ul>"
      end
      private_class_method :conflict_sections

      def escape(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end
      private_class_method :escape
    end
  end
end
