# frozen_string_literal: true

require "json"

module Ibex
  module IR
    # Stable JSON serialization for the current pipeline IR.
    # rubocop:disable Metrics/ModuleLength -- explicit fields keep serialization changes auditable.
    # rubocop:disable Lint/SelfAssignment -- RBS inline assertions narrow schema-decoded values in place.
    module Serialize
      # @rbs!
      #   type serialized_value = untyped
      # @rbs!
      #   private def validate_version: (Hash[String, serialized_value] data) -> void
      #   private def self.validate_version: (Hash[String, serialized_value] data) -> void
      #   private def load_grammar: (Hash[String, serialized_value] data) -> Grammar
      #   private def self.load_grammar: (Hash[String, serialized_value] data) -> Grammar
      #   private def load_automaton: (Hash[String, serialized_value] data) -> Automaton
      #   private def self.load_automaton: (Hash[String, serialized_value] data) -> Automaton
      #   private def load_lexer: (Hash[String, serialized_value] data) -> Lexer
      #   private def self.load_lexer: (Hash[String, serialized_value] data) -> Lexer
      #   private def load_state: (Hash[String, serialized_value] state, Grammar grammar) -> AutomatonState
      #   private def self.load_state: (Hash[String, serialized_value] state, Grammar grammar) -> AutomatonState
      #   private def symbol_keyed: (Hash[String, serialized_value] values, Grammar grammar,
      #     ?actions: bool) -> Hash[Integer, serialized_value]
      #   private def self.symbol_keyed: (Hash[String, serialized_value] values, Grammar grammar,
      #     ?actions: bool) -> Hash[Integer, serialized_value]
      #   private def normalize_action: (Hash[String, serialized_value] value) -> parser_action?
      #   private def self.normalize_action: (Hash[String, serialized_value] value) -> parser_action?
      #   private def load_production: (Hash[String, serialized_value] production) -> Production
      #   private def self.load_production: (Hash[String, serialized_value] production) -> Production
      #   private def load_user_code_chunks: (Hash[String,
      #     Array[Hash[String, serialized_value]]] chunks) -> user_code_chunks
      #   private def self.load_user_code_chunks: (Hash[String,
      #     Array[Hash[String, serialized_value]]] chunks) -> user_code_chunks
      #   private def load_symbol_metadata: (Hash[String, serialized_value] symbol, String field) -> String?
      #   private def self.load_symbol_metadata: (Hash[String, serialized_value] symbol, String field) -> String?
      #   private def load_grammar_tests: (Array[Hash[String, serialized_value]] tests) -> Array[grammar_test]
      #   private def self.load_grammar_tests: (Array[Hash[String, serialized_value]] tests) -> Array[grammar_test]
      #   private def symbol_source_position: (Hash[String, serialized_value] symbol) -> String
      #   private def self.symbol_source_position: (Hash[String, serialized_value] symbol) -> String
      #   private def symbolize: (serialized_value value) -> serialized_value
      #   private def self.symbolize: (serialized_value value) -> serialized_value

      # @rbs (Grammar | Automaton | Lexer value) -> String
      def dump(value)
        normalize = lambda do |entry|
          case entry
          when String
            normalized = entry.dup.force_encoding(Encoding::UTF_8)
            normalized.valid_encoding? ? normalized : normalized.scrub
          when Array
            entry.map { |child| normalize.call(child) }
          when Hash
            entry.to_h { |key, child| [normalize.call(key), normalize.call(child)] }
          else
            entry
          end
        end
        "#{JSON.pretty_generate(normalize.call(value.to_h))}\n"
      end
      module_function :dump

      # @rbs (String source) -> (Grammar | Automaton | Lexer)
      def load(source)
        data = JSON.parse(source) #: Hash[String, serialized_value]
        type = data.fetch("ibex_ir") #: String
        return load_lexer(data) if type == "lexer"

        validate_version(data)
        return load_grammar(data) if type == "grammar"
        return load_automaton(data) if type == "automaton"

        raise Ibex::Error, "(ir):1:1: unsupported IR type #{type.inspect}"
      rescue JSON::ParserError => e
        raise Ibex::Error, "(ir):1:1: invalid JSON: #{e.message}"
      end
      module_function :load

      private

      # @rbs skip
      def validate_version(data)
        version = data["schema_version"]
        return if SUPPORTED_SCHEMA_VERSIONS.include?(version)

        expected = SUPPORTED_SCHEMA_VERSIONS.join(", ")
        raise Ibex::Error, "(ir):1:1: unsupported schema_version #{version.inspect}; expected the current format (#{expected})"
      end

      # @rbs skip
      def load_grammar(data)
        data = data #: Hash[String, untyped]
        empty_chunks = {} #: Hash[String, serialized_value]
        empty_parameters = [] #: Array[serialized_value]
        empty_printers = [] #: Array[serialized_value]
        empty_tests = [] #: Array[serialized_value]
        empty_recovery = { "sync_tokens" => [], "on_error_reduce" => [] } #: Hash[String, serialized_value]
        data.fetch("schema_version") #: Integer
        symbols_data = data.fetch("symbols") #: Array[Hash[String, serialized_value]]
        symbols = symbols_data.map do |symbol|
          GrammarSymbol.new(id: symbol.fetch("id"), name: symbol.fetch("name"), kind: symbol.fetch("kind"),
                            reserved: symbol.fetch("reserved"), precedence: symbolize(symbol["prec"]),
                            location: symbolize(symbol["loc"]),
                            display_name: load_symbol_metadata(symbol, "display_name"),
                            semantic_type: load_symbol_metadata(symbol, "semantic_type"),
                            documentation: symbol["doc"])
        end
        productions_data = data.fetch("productions") #: Array[Hash[String, serialized_value]]
        productions = productions_data.map { |production| load_production(production) }
        Grammar.new(
          class_name: data.fetch("class_name"), superclass: data["superclass"], start: data.fetch("start"),
          expect: data.fetch("expect"), options: symbolize(data.fetch("options")), symbols: symbols,
          mode: (data["mode"] || "default").to_sym, starts: data["starts"], expect_rr: data["expect_rr"],
          parser_parameters: symbolize(data.fetch("params", empty_parameters)),
          value_printers: symbolize(data.fetch("printers", empty_printers)),
          grammar_tests: load_grammar_tests(data.fetch("tests", empty_tests)),
          lexer: data["lexer"] && load_lexer(data.fetch("lexer")),
          recovery: symbolize(data.fetch("recovery", empty_recovery)), productions: productions,
          user_code: data.fetch("user_code"), conversions: data.fetch("conversions"),
          warnings: symbolize(data.fetch("warnings")),
          user_code_chunks: load_user_code_chunks(data.fetch("user_code_chunks", empty_chunks)),
          source_provenance: symbolize(data["source_provenance"]),
          parser_contract: load_parser_contract(data.fetch("parser_contract"))
        )
      end # rubocop:enable Metrics/AbcSize

      # @rbs skip
      def load_automaton(data)
        data = data #: Hash[String, untyped]
        grammar_data = data.fetch("grammar") #: Hash[String, serialized_value]
        grammar = load_grammar(grammar_data)
        states_data = data.fetch("states") #: Array[Hash[String, serialized_value]]
        states = states_data.map { |state| load_state(state, grammar) }
        data.fetch("schema_version") #: Integer
        Automaton.new(
          grammar: grammar, states: states, conflict_summary: symbolize(data.fetch("conflict_summary")),
          algorithm: data.fetch("algorithm"), grammar_digest: data.fetch("grammar_digest"),
          entry_states: data["entry_states"], entry_construction: data.fetch("entry_construction")
        )
      end

      # @rbs skip
      def load_lexer(data)
        data = data #: Hash[String, untyped]
        version = data.fetch("schema_version") #: Integer
        unless SUPPORTED_LEXER_SCHEMA_VERSIONS.include?(version)
          expected = SUPPORTED_LEXER_SCHEMA_VERSIONS.join(", ")
          raise Ibex::Error,
                "(ir):1:1: unsupported lexer schema_version #{version.inspect}; expected the current lexer format (#{expected})"
        end
        rules_data = data.fetch("rules") #: Array[Hash[String, serialized_value]]
        rules = rules_data.map do |rule|
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
        state = state #: Hash[String, untyped]
        items_data = state.fetch("items") #: Array[Hash[String, serialized_value]]
        items = items_data.map do |item|
          lookahead_names = item.fetch("lookaheads") #: Array[String]
          lookaheads = lookahead_names.map do |name|
            symbol = grammar.symbol(name) || raise(Ibex::Error, "(ir):1:1: unknown symbol #{name.inspect}")
            symbol.id
          end
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
      # @rbs (Hash[String, serialized_value] values, Grammar grammar, ?actions: bool) -> Hash[Integer, serialized_value]
      def symbol_keyed(values, grammar, actions: false)
        values = values #: Hash[String, untyped]
        values.to_h do |name, value|
          symbol = grammar.symbol(name) || raise(Ibex::Error, "(ir):1:1: unknown symbol #{name.inspect}")
          [symbol.id, actions ? normalize_action(value) : value]
        end
      end

      # @rbs skip
      def normalize_action(value)
        value = value #: untyped
        return nil unless value

        action = symbolize(value)
        action[:type] = action[:type].to_sym
        action
      end

      # @rbs skip
      def load_production(production)
        production = production #: Hash[String, untyped]
        action_data = production["action"]
        action_data = action_data #: Hash[String, untyped] if action_data
        action = if action_data
                   Action.new(code: action_data.fetch("code"), location: symbolize(action_data["loc"]),
                              named_refs: symbolize(action_data.fetch("named_refs")),
                              context_length: action_data.fetch("context_length"),
                              composition: symbolize(action_data["composition"]))
                 end
        Production.new(id: production.fetch("id"), lhs: production.fetch("lhs"), rhs: production.fetch("rhs"),
                       action: action, precedence_override: production["prec_override"],
                       origin: symbolize(production.fetch("origin")), documentation: production["doc"],
                       expansion: symbolize(production["expansion"]), node: symbolize(production["node"]))
      end

      # @rbs skip
      def load_user_code_chunks(chunks)
        chunks = chunks #: Hash[String, Array[Hash[String, untyped]]]
        chunks.to_h do |name, values|
          loaded = values.map do |value|
            UserCodeChunk.new(code: value.fetch("code"), location: symbolize(value.fetch("loc")))
          end
          [name, loaded]
        end
      end

      # @rbs skip
      def load_symbol_metadata(symbol, field)
        symbol = symbol #: Hash[String, untyped]
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
        tests = tests #: Array[untyped]
        symbolize(tests).map { |test| test.merge(expectation: test.fetch(:expectation).to_sym) }
      end

      def load_parser_contract(value)
        value = value #: Hash[String, untyped]

        entries = ParserContract::DEFINITIONS.keys.to_h do |key|
          entry = value.fetch(key.to_s)
          location = entry["loc"]
          loaded_location = if location
                              Location.new(
                                file: location.fetch("file"), line: location.fetch("line"),
                                column: location.fetch("column")
                              )
                            end
          [
            key,
            ParserContract::Entry.new(
              key, value: entry["value"]&.to_sym, explicit: entry.fetch("explicit"), location: loaded_location
            )
          ]
        end
        ParserContract.new(**entries)
      end

      # @rbs skip
      # Parsed IR values are recursively heterogeneous until schema validation narrows them.
      # @rbs (serialized_value value) -> serialized_value
      def symbolize(value)
        value = value #: untyped
        case value
        when Array then value.map { |item| symbolize(item) }
        when Hash then value.to_h { |key, item| [key.to_sym, symbolize(item)] }
        else value
        end
      end
      module_function :validate_version, :load_grammar, :load_automaton, :load_lexer, :load_state, :symbol_keyed,
                      :normalize_action, :load_production, :load_user_code_chunks, :load_symbol_metadata,
                      :symbol_source_position, :load_grammar_tests,
                      :load_parser_contract, :symbolize

      class << self
        private :validate_version, :load_grammar, :load_automaton, :load_lexer, :load_state, :symbol_keyed,
                :normalize_action, :load_production, :load_user_code_chunks, :load_symbol_metadata,
                :symbol_source_position, :load_grammar_tests,
                :load_parser_contract, :symbolize
      end
    end
    # rubocop:enable Lint/SelfAssignment
    # rubocop:enable Metrics/ModuleLength
  end
end
