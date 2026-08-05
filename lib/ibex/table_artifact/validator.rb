# frozen_string_literal: true

require_relative "validator/support"
require_relative "validator/tables"
require_relative "validator/metadata"

module Ibex
  module TableArtifact
    # Closed structural and referential validation for untrusted sidecars.
    class Validator
      include ValidationSupport

      ROOT_KEYS = %w[artifact_type schema_version identity payload cost].freeze
      PAYLOAD_KEYS = %w[
        table_format source state_count symbols tokens entry_states tables productions cst recovery semantic_actions
      ].freeze

      class << self
        def validate!(data)
          new(data).validate!
        end
      end

      def initialize(data)
        @data = data
      end

      # rubocop:disable Naming/PredicateMethod -- bang denotes fail-fast validation.
      def validate!
        record(@data, "$", ROOT_KEYS)
        payload = record(@data.fetch("payload"), "$.payload", PAYLOAD_KEYS)
        validate_root_identity
        representation = validate_table_format(payload.fetch("table_format"))
        validate_source(payload.fetch("source"))
        state_count = integer(payload.fetch("state_count"), "$.payload.state_count", minimum: 1)
        symbols = validate_symbols(payload.fetch("symbols"))
        validate_tokens(payload.fetch("tokens"), symbols)
        validate_entries(payload.fetch("entry_states"), symbols, state_count)
        productions = validate_productions(payload.fetch("productions"), symbols)
        TableValidator.new(
          payload.fetch("tables"), state_count: state_count, production_count: productions.length,
                                   terminal_ids: symbol_ids(symbols, "terminal"),
                                   nonterminal_ids: symbol_ids(symbols, "nonterminal"),
                                   representation: representation
        ).validate!
        MetadataValidator.new(payload, symbols: symbols, productions: productions).validate!
        validate_cost(@data.fetch("cost"), payload)
        true
      end
      # rubocop:enable Naming/PredicateMethod

      private

      def validate_root_identity
        invalid("$.artifact_type", "is unsupported") unless @data.fetch("artifact_type") == ARTIFACT_TYPE
        invalid("$.schema_version", "is unsupported") unless @data.fetch("schema_version") == SCHEMA_VERSION
        identity_keys = %w[
          grammar_digest automaton_digest payload_digest cst_metadata_digest recovery_metadata_digest
        ]
        identity = record(@data.fetch("identity"), "$.identity", identity_keys)
        identity.each { |key, value| digest(value, "$.identity.#{key}") }
        expected = Serializer.digest(@data.fetch("payload"))
        invalid("$.identity.payload_digest", "does not match the canonical payload") unless
          identity.fetch("payload_digest") == expected
        payload = @data.fetch("payload")
        validate_named_digest(identity, payload, "cst_metadata", "cst")
        validate_named_digest(identity, payload, "recovery_metadata", "recovery")
      end

      def validate_table_format(data)
        path = "$.payload.table_format"
        keys = %w[family version representation action_encoding goto_encoding]
        record(data, path, keys)
        enum(data.fetch("family"), "#{path}.family", ["ibex-runtime-parser-table"])
        invalid("#{path}.version", "must be 6") unless integer(data.fetch("version"), "#{path}.version") == 6
        representation = enum(data.fetch("representation"), "#{path}.representation", %w[plain compact])
        expected = if representation == "compact"
                     %w[signed-row-displacement-v1 row-displacement-v1]
                   else
                     %w[signed-sparse-rows-v1 sparse-rows-v1]
                   end
        actual = [data.fetch("action_encoding"), data.fetch("goto_encoding")]
        invalid(path, "encodings do not match representation") unless actual == expected
        representation
      end

      def validate_source(data)
        source = record(data, "$.payload.source", %w[grammar_digest automaton_digest])
        source.each { |key, value| digest(value, "$.payload.source.#{key}") }
        identity = @data.fetch("identity")
        invalid("$.payload.source", "must match root identity") unless
          source.fetch("grammar_digest") == identity.fetch("grammar_digest") &&
          source.fetch("automaton_digest") == identity.fetch("automaton_digest")
      end

      def validate_symbols(data)
        symbols = array(data, "$.payload.symbols")
        invalid("$.payload.symbols", "must not be empty") if symbols.empty?
        names = []
        symbols.each_with_index do |symbol, index|
          path = "$.payload.symbols[#{index}]"
          record(symbol, path, %w[id name kind display_name])
          invalid("#{path}.id", "must be contiguous and ordered") unless symbol.fetch("id") == index
          names << string(symbol.fetch("name"), "#{path}.name")
          enum(symbol.fetch("kind"), "#{path}.kind", %w[terminal nonterminal])
          nullable_string(symbol.fetch("display_name"), "#{path}.display_name")
        end
        invalid("$.payload.symbols", "names must be unique") unless names.uniq.length == names.length
        symbols
      end

      def validate_tokens(data, symbols)
        tokens = array(data, "$.payload.tokens")
        expected = symbols.select { |symbol| symbol.fetch("kind") == "terminal" }.map do |symbol|
          symbol.slice("id", "name", "display_name")
        end
        tokens.each_with_index do |token, index|
          record(token, "$.payload.tokens[#{index}]", %w[id name display_name])
        end
        invalid("$.payload.tokens", "must exactly index terminal symbols") unless tokens == expected
        invalid("$.payload.tokens", "token id 0 must be $eof") unless tokens.first&.fetch("id")&.zero? &&
                                                                      tokens.first.fetch("name") == "$eof"
      end

      def validate_entries(data, symbols, state_count)
        entries = array(data, "$.payload.entry_states")
        invalid("$.payload.entry_states", "must not be empty") if entries.empty?
        names = entries.map.with_index do |entry, index|
          path = "$.payload.entry_states[#{index}]"
          record(entry, path, %w[name state])
          name = string(entry.fetch("name"), "#{path}.name")
          symbol = symbols.find { |candidate| candidate.fetch("name") == name }
          invalid("#{path}.name", "must reference a nonterminal") unless symbol&.fetch("kind") == "nonterminal"
          state = integer(entry.fetch("state"), "#{path}.state", minimum: 0)
          invalid("#{path}.state", "references a missing state") unless state < state_count
          name
        end
        invalid("$.payload.entry_states", "names must be unique") unless names.uniq.length == names.length
      end

      def validate_productions(data, symbols)
        productions = array(data, "$.payload.productions")
        nonterminals = symbol_ids(symbols, "nonterminal")
        productions.each_with_index do |production, index|
          path = "$.payload.productions[#{index}]"
          record(production, path, %w[id lhs rhs rhs_length action_slot])
          invalid("#{path}.id", "must be contiguous and ordered") unless production.fetch("id") == index
          lhs = integer(production.fetch("lhs"), "#{path}.lhs", minimum: 0)
          invalid("#{path}.lhs", "must reference a nonterminal") unless nonterminals.include?(lhs)
          rhs = array(production.fetch("rhs"), "#{path}.rhs")
          rhs.each_with_index do |symbol_id, rhs_index|
            integer(symbol_id, "#{path}.rhs[#{rhs_index}]", minimum: 0)
            invalid("#{path}.rhs[#{rhs_index}]", "references a missing symbol") unless symbol_id < symbols.length
          end
          invalid("#{path}.rhs_length", "must match rhs") unless production.fetch("rhs_length") == rhs.length
          slot = nullable_integer(production.fetch("action_slot"), "#{path}.action_slot", minimum: 0)
          invalid("#{path}.action_slot", "must equal production id") if slot && slot != index
        end
        productions
      end

      def validate_cost(data, payload)
        path = "$.cost"
        keys = %w[
          canonical_payload_bytes action_cells goto_cells lookup_cost recognition_cost measurement bounded_by_max_steps
        ]
        record(data, path, keys)
        bytes = integer(data.fetch("canonical_payload_bytes"), "#{path}.canonical_payload_bytes", minimum: 1)
        unless bytes == Serializer.compact(payload).bytesize
          invalid("#{path}.canonical_payload_bytes",
                  "does not match payload")
        end
        action_cells = integer(data.fetch("action_cells"), "#{path}.action_cells", minimum: 0)
        goto_cells = integer(data.fetch("goto_cells"), "#{path}.goto_cells", minimum: 0)
        tables = payload.fetch("tables")
        invalid("#{path}.action_cells", "does not match actions") unless action_cells == occupied(
          tables.fetch("actions"), "codes"
        )
        invalid("#{path}.goto_cells", "does not match gotos") unless goto_cells == occupied(tables.fetch("gotos"),
                                                                                            "values")
        expected_lookup, expected_recognition = expected_costs(payload)
        invalid("#{path}.lookup_cost", "does not match table representation") unless
          data.fetch("lookup_cost") == expected_lookup
        invalid("#{path}.recognition_cost", "does not match table representation") unless
          data.fetch("recognition_cost") == expected_recognition
        enum(data.fetch("measurement"), "#{path}.measurement", ["not-measured"])
        invalid("#{path}.bounded_by_max_steps", "must be true") unless boolean(data.fetch("bounded_by_max_steps"),
                                                                               "#{path}.bounded_by_max_steps")
      end

      def expected_costs(payload)
        compact = payload.fetch("table_format").fetch("representation") == "compact"
        lookup = compact ? "O(1) row-displacement probe" : "O(log row width) binary search"
        recognition = if compact
                        "O(input tokens + reductions)"
                      else
                        "O((input tokens + reductions) * log maximum row width)"
                      end
        [lookup, "#{recognition}; lexer, recovery search, and semantic actions excluded"]
      end

      def occupied(table, values_key)
        return table.fetch("rows").sum(&:length) if table.key?("rows")

        table.fetch(values_key).compact.length
      end

      def symbol_ids(symbols, kind)
        symbols.filter_map { |symbol| symbol.fetch("id") if symbol.fetch("kind") == kind }.to_set
      end

      def validate_named_digest(identity, payload, identity_name, payload_name)
        expected = Serializer.digest(payload.fetch(payload_name))
        path = "$.identity.#{identity_name}_digest"
        return if identity.fetch("#{identity_name}_digest") == expected

        invalid(path,
                "does not match payload #{payload_name}")
      end
    end
  end
end
