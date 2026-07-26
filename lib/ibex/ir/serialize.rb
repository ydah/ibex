# frozen_string_literal: true

require "json"

module Ibex
  module IR
    # Stable JSON serialization for versioned pipeline IR.
    # rubocop:disable Metrics/ModuleLength -- explicit versioned fields keep serialization changes auditable.
    module Serialize
      # @rbs!
      #   private def validate_version: (untyped data) -> untyped
      #   private def self.validate_version: (untyped data) -> untyped
      #   private def load_grammar: (untyped data) -> untyped
      #   private def self.load_grammar: (untyped data) -> untyped
      #   private def load_automaton: (untyped data) -> untyped
      #   private def self.load_automaton: (untyped data) -> untyped
      #   private def load_lexer: (untyped data) -> untyped
      #   private def self.load_lexer: (untyped data) -> untyped
      #   private def load_state: (untyped state, untyped grammar) -> untyped
      #   private def self.load_state: (untyped state, untyped grammar) -> untyped
      #   private def symbol_keyed: (untyped values, untyped grammar, ?actions: untyped) -> untyped
      #   private def self.symbol_keyed: (untyped values, untyped grammar, ?actions: untyped) -> untyped
      #   private def normalize_action: (untyped value) -> untyped
      #   private def self.normalize_action: (untyped value) -> untyped
      #   private def load_production: (untyped production, Integer schema_version) -> untyped
      #   private def self.load_production: (untyped production, Integer schema_version) -> untyped
      #   private def load_user_code_chunks: (untyped chunks) -> untyped
      #   private def self.load_user_code_chunks: (untyped chunks) -> untyped
      #   private def load_symbol_metadata: (untyped symbol, String field) -> String?
      #   private def self.load_symbol_metadata: (untyped symbol, String field) -> String?
      #   private def load_grammar_tests: (untyped tests) -> untyped
      #   private def self.load_grammar_tests: (untyped tests) -> untyped
      #   private def symbol_source_position: (untyped symbol) -> String
      #   private def self.symbol_source_position: (untyped symbol) -> String
      #   private def symbolize: (untyped value) -> untyped
      #   private def self.symbolize: (untyped value) -> untyped

      # @rbs (Grammar | Automaton | Lexer value) -> String
      def dump(value)
        "#{JSON.pretty_generate(value.to_h)}\n"
      end
      module_function :dump

      # @rbs (String source) -> (Grammar | Automaton | Lexer)
      def load(source)
        data = JSON.parse(source)
        type = data.fetch("ibex_ir") { raise Ibex::Error, "(ir):1:1: missing ibex_ir discriminator" }
        return load_lexer(data) if type == "lexer"

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
        return if SUPPORTED_SCHEMA_VERSIONS.include?(version)

        expected = SUPPORTED_SCHEMA_VERSIONS.join(", ")
        raise Ibex::Error, "(ir):1:1: unsupported schema_version #{version.inspect}; expected one of #{expected}"
      end

      # @rbs skip
      def load_grammar(data) # rubocop:disable Metrics/AbcSize -- explicit fields preserve the public IR contract.
        empty_chunks = {} #: Hash[String, untyped]
        empty_parameters = [] #: Array[untyped]
        empty_printers = [] #: Array[untyped]
        empty_tests = [] #: Array[untyped]
        empty_recovery = { "sync_tokens" => [], "on_error_reduce" => [] } #: Hash[String, untyped]
        schema_version = data.fetch("schema_version")
        symbols = data.fetch("symbols").map do |symbol|
          GrammarSymbol.new(id: symbol.fetch("id"), name: symbol.fetch("name"), kind: symbol.fetch("kind"),
                            reserved: symbol.fetch("reserved"), precedence: symbolize(symbol["prec"]),
                            location: symbolize(symbol["loc"]),
                            display_name: load_symbol_metadata(symbol, "display_name"),
                            semantic_type: load_symbol_metadata(symbol, "semantic_type"),
                            documentation: symbol["doc"])
        end
        productions = data.fetch("productions").map { |production| load_production(production, schema_version) }
        Grammar.new(class_name: data.fetch("class_name"), superclass: data["superclass"], start: data.fetch("start"),
                    expect: data.fetch("expect"), options: symbolize(data.fetch("options")), symbols: symbols,
                    mode: (data["mode"] || "racc").to_sym,
                    starts: data["starts"],
                    expect_rr: data["expect_rr"],
                    parser_parameters: symbolize(data.fetch("params", empty_parameters)),
                    value_printers: symbolize(data.fetch("printers", empty_printers)),
                    grammar_tests: load_grammar_tests(data.fetch("tests", empty_tests)),
                    lexer: data["lexer"] && load_lexer(data.fetch("lexer")),
                    recovery: symbolize(data.fetch("recovery", empty_recovery)),
                    productions: productions, user_code: data.fetch("user_code"),
                    conversions: data.fetch("conversions"), warnings: symbolize(data.fetch("warnings")),
                    user_code_chunks: load_user_code_chunks(data.fetch("user_code_chunks", empty_chunks)),
                    schema_version: schema_version, source_provenance: symbolize(data["source_provenance"]),
                    migration: symbolize(data["migration"]))
      end # rubocop:enable Metrics/AbcSize

      # @rbs skip
      def load_automaton(data)
        grammar = load_grammar(data.fetch("grammar"))
        states = data.fetch("states").map { |state| load_state(state, grammar) }
        Automaton.new(grammar: grammar, states: states, conflict_summary: symbolize(data.fetch("conflict_summary")),
                      algorithm: data.fetch("algorithm"), grammar_digest: data.fetch("grammar_digest"),
                      schema_version: data.fetch("schema_version"), entry_states: data["entry_states"])
      end

      # @rbs skip
      def load_lexer(data)
        version = data.fetch("schema_version")
        unless SUPPORTED_LEXER_SCHEMA_VERSIONS.include?(version)
          expected = SUPPORTED_LEXER_SCHEMA_VERSIONS.join(", ")
          raise Ibex::Error,
                "(ir):1:1: unsupported lexer schema_version #{version.inspect}; expected one of #{expected}"
        end
        rules = data.fetch("rules").map do |rule|
          LexerRule.new(
            id: rule.fetch("id"), state: rule.fetch("state"), kind: rule.fetch("kind").to_sym,
            token: rule["token"], pattern: rule.fetch("pattern"), pattern_kind: rule.fetch("pattern_kind").to_sym,
            options: rule.fetch("options"), action: rule["action"], location: symbolize(rule.fetch("loc"))
          )
        end
        Lexer.new(
          states: data.fetch("states"), rules: rules, warnings: symbolize(data.fetch("warnings")),
          schema_version: version, source_provenance: symbolize(data["source_provenance"])
        )
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
      def load_production(production, schema_version)
        action_data = production["action"]
        action = if action_data
                   Action.new(code: action_data.fetch("code"), location: symbolize(action_data["loc"]),
                              named_refs: symbolize(action_data.fetch("named_refs")),
                              context_length: action_data.fetch("context_length"),
                              composition: symbolize(action_data["composition"]))
                 end
        Production.new(id: production.fetch("id"), lhs: production.fetch("lhs"), rhs: production.fetch("rhs"),
                       action: action, precedence_override: production["prec_override"],
                       origin: symbolize(production.fetch("origin")), documentation: production["doc"],
                       expansion: schema_version >= 2 ? symbolize(production["expansion"]) : nil)
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
      def load_grammar_tests(tests)
        symbolize(tests).map { |test| test.merge(expectation: test.fetch(:expectation).to_sym) }
      end

      # @rbs skip
      def symbolize(value)
        case value
        when Array then value.map { |item| symbolize(item) }
        when Hash then value.to_h { |key, item| [key.to_sym, symbolize(item)] }
        else value
        end
      end
      module_function :validate_version, :load_grammar, :load_automaton, :load_lexer, :load_state, :symbol_keyed,
                      :normalize_action, :load_production, :load_user_code_chunks, :load_symbol_metadata,
                      :symbol_source_position, :load_grammar_tests, :symbolize

      class << self
        private :validate_version, :load_grammar, :load_automaton, :load_lexer, :load_state, :symbol_keyed,
                :normalize_action, :load_production, :load_user_code_chunks, :load_symbol_metadata,
                :symbol_source_position, :load_grammar_tests, :symbolize
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
