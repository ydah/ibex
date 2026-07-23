# frozen_string_literal: true

require_relative "symbol_labels"

module Ibex
  module Codegen
    # Renders a self-contained navigable automaton report.
    module HTML
      # @rbs!
      #   private def state_sections: (IR::Automaton automaton, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> String
      #   private def self.state_sections: (IR::Automaton automaton, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> String
      #   private def controls: (IR::Automaton automaton) -> String
      #   private def self.controls: (IR::Automaton automaton) -> String
      #   private def styles: () -> String
      #   private def self.styles: () -> String
      #   private def interaction_script: () -> String
      #   private def self.interaction_script: () -> String
      #   private def one_hop_neighbors: (IR::Automaton automaton, Integer state_id) -> Array[Integer]
      #   private def self.one_hop_neighbors: (IR::Automaton automaton, Integer state_id) -> Array[Integer]
      #   private def item_html: (IR::AutomatonItem item, IR::Grammar grammar, Hash[Integer, String] labels) -> String
      #   private def self.item_html: (IR::AutomatonItem item, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> String
      #   private def rule_sections: (IR::Grammar grammar, Hash[Integer, String] labels) -> String
      #   private def self.rule_sections: (IR::Grammar grammar, Hash[Integer, String] labels) -> String
      #   private def conflict_sections: (IR::Automaton automaton, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> String
      #   private def self.conflict_sections: (IR::Automaton automaton, IR::Grammar grammar,
      #     Hash[Integer, String] labels) -> String
      #   private def escape: (String value) -> String
      #   private def self.escape: (String value) -> String
      #   private def symbol_name: (Hash[Integer, String] labels, Integer id) -> String
      #   private def self.symbol_name: (Hash[Integer, String] labels, Integer id) -> String

      # @rbs (IR::Automaton automaton) -> String
      def render(automaton)
        grammar = automaton.grammar
        labels = SymbolLabels.build(grammar)
        <<~HTML
          <!doctype html>
          <html lang="en"><head><meta charset="utf-8"><title>Ibex automaton</title>
          #{styles}
          </head><body><h1>Ibex #{escape(automaton.algorithm)} automaton</h1>
          <nav><a href="#rules">Rules</a> · <a href="#conflicts">Conflicts</a></nav>
          #{controls(automaton)}
          <main id="states">#{state_sections(automaton, grammar, labels)}</main>
          <h2 id="rules">Rules</h2>#{rule_sections(grammar, labels)}
          <h2 id="conflicts">Conflicts</h2>#{conflict_sections(automaton, grammar, labels)}
          #{interaction_script}
          </body></html>
        HTML
      end
      module_function :render

      # @rbs skip
      private

      # @rbs skip
      def styles
        <<~HTML
          <style>
          body{font:14px system-ui;margin:2rem;max-width:90rem}code{white-space:pre-wrap}
          .controls{align-items:center;display:flex;flex-wrap:wrap;gap:1rem;margin:1rem 0}
          .state{border:1px solid #bbb;padding:1rem;margin:1rem 0}.state[hidden]{display:none}
          .conflict-state{background:#fff7f7;border:2px solid #b91c1c}.conflict{color:#a00}a{color:#075985}
          </style>
        HTML
      end

      # @rbs skip
      def interaction_script
        <<~HTML
          <script>
          (() => {
            const search = document.getElementById("state-search");
            const conflictOnly = document.getElementById("conflict-only");
            const neighborhood = document.getElementById("conflict-neighborhood");
            const states = Array.from(document.querySelectorAll(".state"));
            const update = () => {
              const query = search.value.trim().toLowerCase();
              const focus = neighborhood.value;
              states.forEach((state) => {
                const matchesText = !query || state.textContent.toLowerCase().includes(query);
                const matchesConflict = !conflictOnly.checked || state.classList.contains("conflict-state");
                const nearby = !focus || state.dataset.neighbors.split(" ").includes(focus);
                state.hidden = !(matchesText && matchesConflict && nearby);
              });
            };
            search.addEventListener("input", update);
            conflictOnly.addEventListener("change", update);
            neighborhood.addEventListener("change", update);
          })();
          </script>
        HTML
      end

      # @rbs skip
      def controls(automaton)
        options = automaton.states.filter_map do |state|
          next if state.conflicts.empty?

          %(<option value="#{state.id}">State #{state.id}</option>)
        end.join
        <<~HTML
          <div class="controls">
          <label>Search states <input id="state-search" type="search" aria-controls="states"></label>
          <label><input id="conflict-only" type="checkbox"> Conflicts only</label>
          <label>Conflict neighborhood
          <select id="conflict-neighborhood"><option value="">All states</option>#{options}</select></label>
          </div>
        HTML
      end

      # @rbs skip
      def state_sections(automaton, grammar, labels)
        automaton.states.map do |state|
          transitions = state.transitions.map do |symbol_id, target|
            symbol = escape(symbol_name(labels, symbol_id))
            "<li>#{symbol} → <a href=\"#state-#{target}\">state #{target}</a></li>"
          end.join
          items = state.items.map { |item| item_html(item, grammar, labels) }.join
          class_name = state.conflicts.empty? ? "state" : "state conflict-state"
          neighbors = one_hop_neighbors(automaton, state.id).join(" ")
          <<~HTML
            <section class="#{class_name}" id="state-#{state.id}" data-state-id="#{state.id}" data-neighbors="#{neighbors}">
            <h2>State #{state.id}</h2>
            <ul>#{transitions}</ul><ul>#{items}</ul></section>
          HTML
        end.join
      end

      # @rbs skip
      def one_hop_neighbors(automaton, state_id)
        outgoing = automaton.states.fetch(state_id).transitions.values
        incoming = automaton.states.filter_map do |state|
          state.id if state.transitions.value?(state_id)
        end
        ([state_id] + outgoing + incoming).uniq.sort
      end

      # @rbs skip
      def item_html(item, grammar, labels)
        return "<li><code>$accept</code></li>" if item.production.negative?

        production = grammar.productions.fetch(item.production)
        lhs = symbol_name(labels, production.lhs)
        rhs = production.rhs.map { |id| symbol_name(labels, id) }.insert(item.dot, "•").join(" ")
        link = "<a href=\"#rule-#{production.id}\">rule #{production.id}</a>"
        "<li>#{link} <code>#{escape(lhs)} → #{escape(rhs)}</code></li>"
      end

      # @rbs skip
      def rule_sections(grammar, labels)
        grammar.productions.map do |production|
          lhs = symbol_name(labels, production.lhs)
          rhs = production.rhs.map { |id| symbol_name(labels, id) }.join(" ")
          number = "<strong>#{production.id}</strong>"
          "<p id=\"rule-#{production.id}\">#{number} <code>#{escape(lhs)} → #{escape(rhs)}</code></p>"
        end.join
      end

      # @rbs skip
      def conflict_sections(automaton, grammar, labels)
        conflicts = automaton.states.flat_map do |state|
          state.conflicts.map do |conflict|
            link = "<a href=\"#state-#{state.id}\">state #{state.id}</a>"
            symbol = grammar.symbol(conflict[:symbol])
            displayed = symbol ? conflict.merge(symbol: symbol_name(labels, symbol.id)) : conflict
            "<li class=\"conflict\">#{link}: #{escape(displayed.inspect)}</li>"
          end
        end
        conflicts.empty? ? "<p>None</p>" : "<ul>#{conflicts.join}</ul>"
      end

      # @rbs skip
      def escape(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end

      # @rbs skip
      def symbol_name(labels, id)
        labels.fetch(id) { raise Ibex::Error, "missing grammar symbol id #{id}" }
      end
      module_function :styles, :interaction_script, :controls, :state_sections, :one_hop_neighbors
      module_function :item_html, :rule_sections, :conflict_sections, :escape, :symbol_name

      class << self
        private :styles, :interaction_script, :controls, :state_sections, :one_hop_neighbors
        private :item_html, :rule_sections, :conflict_sections, :escape, :symbol_name
      end
    end
  end
end
