# frozen_string_literal: true

require "json"

module Ibex
  module IR
    # Stable JSON serialization for versioned pipeline IR.
    module Serialize
      # @rbs!
      #   private def validate_version: (untyped data) -> untyped
      #   private def self.validate_version: (untyped data) -> untyped
      #   private def load_grammar: (untyped data) -> untyped
      #   private def self.load_grammar: (untyped data) -> untyped
      #   private def load_automaton: (untyped data) -> untyped
      #   private def self.load_automaton: (untyped data) -> untyped
      #   private def load_state: (untyped state, untyped grammar) -> untyped
      #   private def self.load_state: (untyped state, untyped grammar) -> untyped
      #   private def symbol_keyed: (untyped values, untyped grammar, ?actions: untyped) -> untyped
      #   private def self.symbol_keyed: (untyped values, untyped grammar, ?actions: untyped) -> untyped
      #   private def normalize_action: (untyped value) -> untyped
      #   private def self.normalize_action: (untyped value) -> untyped
      #   private def load_production: (untyped production) -> untyped
      #   private def self.load_production: (untyped production) -> untyped
      #   private def load_user_code_chunks: (untyped chunks) -> untyped
      #   private def self.load_user_code_chunks: (untyped chunks) -> untyped
      #   private def load_symbol_metadata: (untyped symbol, String field) -> String?
      #   private def self.load_symbol_metadata: (untyped symbol, String field) -> String?
      #   private def symbol_source_position: (untyped symbol) -> String
      #   private def self.symbol_source_position: (untyped symbol) -> String
      #   private def symbolize: (untyped value) -> untyped
      #   private def self.symbolize: (untyped value) -> untyped

      # @rbs (Grammar | Automaton value) -> String
      def dump(value)
        "#{JSON.pretty_generate(value.to_h)}\n"
      end
      module_function :dump

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
      module_function :load

      # @rbs skip
      private

      # @rbs skip
      def validate_version(data)
        version = data["schema_version"]
        return if version == SCHEMA_VERSION

        raise Ibex::Error, "(ir):1:1: unsupported schema_version #{version.inspect}; expected #{SCHEMA_VERSION}"
      end

      # @rbs skip
      def load_grammar(data)
        empty_chunks = {} #: Hash[String, untyped]
        symbols = data.fetch("symbols").map do |symbol|
          GrammarSymbol.new(id: symbol.fetch("id"), name: symbol.fetch("name"), kind: symbol.fetch("kind"),
                            reserved: symbol.fetch("reserved"), precedence: symbolize(symbol["prec"]),
                            location: symbolize(symbol["loc"]),
                            display_name: load_symbol_metadata(symbol, "display_name"),
                            semantic_type: load_symbol_metadata(symbol, "semantic_type"))
        end
        productions = data.fetch("productions").map { |production| load_production(production) }
        Grammar.new(class_name: data.fetch("class_name"), superclass: data["superclass"], start: data.fetch("start"),
                    expect: data.fetch("expect"), options: symbolize(data.fetch("options")), symbols: symbols,
                    productions: productions, user_code: data.fetch("user_code"),
                    conversions: data.fetch("conversions"), warnings: symbolize(data.fetch("warnings")),
                    user_code_chunks: load_user_code_chunks(data.fetch("user_code_chunks", empty_chunks)))
      end

      # @rbs skip
      def load_automaton(data)
        grammar = load_grammar(data.fetch("grammar"))
        states = data.fetch("states").map { |state| load_state(state, grammar) }
        Automaton.new(grammar: grammar, states: states, conflict_summary: symbolize(data.fetch("conflict_summary")),
                      algorithm: data.fetch("algorithm"), grammar_digest: data.fetch("grammar_digest"))
      end

      # @rbs skip
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

      # @rbs skip
      def symbol_keyed(values, grammar, actions: false)
        values.to_h do |name, value|
          [grammar.symbol(name).id, actions ? normalize_action(value) : value]
        end
      end

      # @rbs skip
      def normalize_action(value)
        return nil unless value

        action = symbolize(value)
        action[:type] = action[:type].to_sym
        action
      end

      # @rbs skip
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

      # @rbs skip
      def load_user_code_chunks(chunks)
        chunks.to_h do |name, values|
          loaded = values.map do |value|
            UserCodeChunk.new(code: value.fetch("code"), location: symbolize(value.fetch("loc")))
          end
          [name, loaded]
        end
      end

      # @rbs skip
      def load_symbol_metadata(symbol, field)
        value = symbol[field]
        return nil if value.nil?

        position = symbol_source_position(symbol)
        raise Ibex::Error, "#{position}: #{field} must be a String or null" unless value.is_a?(String)
        raise Ibex::Error, "#{position}: #{field} must not be empty" if value.strip.empty?
        raise Ibex::Error, "#{position}: #{field} must be a single line" if value.match?(/[\r\n]/)
        raise Ibex::Error, "#{position}: #{field} must not contain control characters" if
          value.match?(/[[:cntrl:]]/)

        value
      end

      # @rbs skip
      def symbol_source_position(symbol)
        location = symbol["loc"]
        return "(ir):1:1" unless location.is_a?(Hash)

        file = location["file"]
        line = location["line"]
        column = location["column"]
        return "(ir):1:1" unless file.is_a?(String) && line.is_a?(Integer) && column.is_a?(Integer)

        "#{file}:#{line}:#{column}"
      end

      # @rbs skip
      def symbolize(value)
        case value
        when Array then value.map { |item| symbolize(item) }
        when Hash then value.to_h { |key, item| [key.to_sym, symbolize(item)] }
        else value
        end
      end
      module_function :validate_version, :load_grammar, :load_automaton, :load_state, :symbol_keyed,
                      :normalize_action, :load_production, :load_user_code_chunks, :load_symbol_metadata,
                      :symbol_source_position, :symbolize

      class << self
        private :validate_version, :load_grammar, :load_automaton, :load_state, :symbol_keyed,
                :normalize_action, :load_production, :load_user_code_chunks, :load_symbol_metadata,
                :symbol_source_position, :symbolize
      end
    end
  end
end
