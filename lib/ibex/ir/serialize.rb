# frozen_string_literal: true

require "json"

module Ibex
  module IR
    # Stable JSON serialization for versioned pipeline IR.
    module Serialize
      module_function

      # @rbs (Grammar | Automaton value) -> String
      def dump(value)
        "#{JSON.pretty_generate(value.to_h)}\n"
      end

      # @rbs (String source) -> (Grammar | Automaton)
      def load(source)
        data = JSON.parse(source)
        type = data.fetch("ibex_ir") { raise Ibex::Error, "(ir):1:1: missing ibex_ir discriminator" }
        validate_version(data)
        return load_grammar(data) if type == "grammar"
        return load_automaton(data) if type == "automaton"

        raise Ibex::Error, "(ir):1:1: unsupported IR type #{type.inspect}"
      rescue JSON::ParserError => e
        raise Ibex::Error, "(ir):1:1: invalid JSON: #{e.message}"
      end

      def validate_version(data)
        version = data["schema_version"]
        return if version == SCHEMA_VERSION

        raise Ibex::Error, "(ir):1:1: unsupported schema_version #{version.inspect}; expected #{SCHEMA_VERSION}"
      end
      private_class_method :validate_version

      def load_grammar(data)
        symbols = data.fetch("symbols").map do |symbol|
          GrammarSymbol.new(id: symbol.fetch("id"), name: symbol.fetch("name"), kind: symbol.fetch("kind"),
                            reserved: symbol.fetch("reserved"), precedence: symbolize(symbol["prec"]),
                            location: symbolize(symbol["loc"]))
        end
        productions = data.fetch("productions").map { |production| load_production(production) }
        Grammar.new(class_name: data.fetch("class_name"), superclass: data["superclass"], start: data.fetch("start"),
                    expect: data.fetch("expect"), options: symbolize(data.fetch("options")), symbols: symbols,
                    productions: productions, user_code: data.fetch("user_code"),
                    conversions: data.fetch("conversions"), warnings: symbolize(data.fetch("warnings")))
      end
      private_class_method :load_grammar

      def load_automaton(data)
        grammar = load_grammar(data.fetch("grammar"))
        states = data.fetch("states").map { |state| load_state(state, grammar) }
        Automaton.new(grammar: grammar, states: states, conflict_summary: symbolize(data.fetch("conflict_summary")),
                      algorithm: data.fetch("algorithm"), grammar_digest: data.fetch("grammar_digest"))
      end
      private_class_method :load_automaton

      def load_state(state, grammar)
        items = state.fetch("items").map do |item|
          lookaheads = item.fetch("lookaheads").map { |name| grammar.symbol(name).id }
          AutomatonItem.new(production: item.fetch("production"), dot: item.fetch("dot"), lookaheads: lookaheads)
        end
        AutomatonState.new(id: state.fetch("id"), items: items,
                           transitions: symbol_keyed(state.fetch("transitions"), grammar),
                           actions: symbol_keyed(state.fetch("actions"), grammar, actions: true),
                           gotos: symbol_keyed(state.fetch("gotos"), grammar),
                           default_action: normalize_action(state["default_action"]),
                           conflicts: symbolize(state.fetch("conflicts")))
      end
      private_class_method :load_state

      def symbol_keyed(values, grammar, actions: false)
        values.to_h do |name, value|
          [grammar.symbol(name).id, actions ? normalize_action(value) : value]
        end
      end
      private_class_method :symbol_keyed

      def normalize_action(value)
        return nil unless value

        action = symbolize(value)
        action[:type] = action[:type].to_sym
        action
      end
      private_class_method :normalize_action

      def load_production(production)
        action_data = production["action"]
        action = if action_data
                   Action.new(code: action_data.fetch("code"), location: symbolize(action_data["loc"]),
                              named_refs: symbolize(action_data.fetch("named_refs")),
                              context_length: action_data.fetch("context_length"))
                 end
        Production.new(id: production.fetch("id"), lhs: production.fetch("lhs"), rhs: production.fetch("rhs"),
                       action: action, precedence_override: production["prec_override"],
                       origin: symbolize(production.fetch("origin")))
      end
      private_class_method :load_production

      def symbolize(value)
        case value
        when Array then value.map { |item| symbolize(item) }
        when Hash then value.to_h { |key, item| [key.to_sym, symbolize(item)] }
        else value
        end
      end
      private_class_method :symbolize
    end
  end
end
