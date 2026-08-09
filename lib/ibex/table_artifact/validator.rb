# frozen_string_literal: true

require_relative "validator/support"
require_relative "validator/tables"
require_relative "validator/metadata"

module Ibex
  module TableArtifact
    # Closed structural and referential validation for untrusted sidecars.
    class Validator
      include ValidationSupport

      ROOT_KEYS = %w[artifact_type schema_version identity payload cost].freeze #: Array[String]
      PAYLOAD_KEYS = %w[
        table_format source state_count symbols tokens entry_states tables productions cst recovery semantic_actions
      ].freeze #: Array[String]

      class << self
        # @rbs (Hash[String, ValidationSupport::json_value] data) -> true
        def validate!(data)
          new(data).validate!
        end
      end

      # @rbs (Hash[String, ValidationSupport::json_value] data) -> void
      def initialize(data)
        @data = data
      end

      # rubocop:disable Naming/PredicateMethod -- bang denotes fail-fast validation.
      # @rbs () -> true
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
        tables = payload.fetch("tables") #: Hash[String, ValidationSupport::json_value]
        TableValidator.new(
          tables,
          state_count: state_count,
          production_count: productions.length,
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

      # @rbs () -> void
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

      # @rbs (ValidationSupport::json_value data) -> String
      def validate_table_format(data)
        path = "$.payload.table_format"
        keys = %w[family version representation action_encoding goto_encoding]
        data = record(data, path, keys)
        enum(data.fetch("family"), "#{path}.family", ["ibex-runtime-parser-table"])
        invalid("#{path}.version", "must be 6") unless integer(data.fetch("version"), "#{path}.version") == 6
        representation = enum(data.fetch("representation"), "#{path}.representation", %w[plain compact]) #: String
        expected = if representation == "compact"
                     %w[signed-row-displacement-v1 row-displacement-v1]
                   else
                     %w[signed-sparse-rows-v1 sparse-rows-v1]
                   end
        actual = [data.fetch("action_encoding"), data.fetch("goto_encoding")]
        invalid(path, "encodings do not match representation") unless actual == expected
        representation
      end

      # @rbs (ValidationSupport::json_value data) -> void
      def validate_source(data)
        source = record(data, "$.payload.source", %w[grammar_digest automaton_digest])
        source.each { |key, value| digest(value, "$.payload.source.#{key}") }
        identity = @data.fetch("identity")
        invalid("$.payload.source", "must match root identity") unless
          source.fetch("grammar_digest") == identity.fetch("grammar_digest") &&
          source.fetch("automaton_digest") == identity.fetch("automaton_digest")
      end

      # @rbs (ValidationSupport::json_value data) -> Array[Hash[String, ValidationSupport::json_value]]
      def validate_symbols(data)
        symbols = array(data, "$.payload.symbols") #: Array[Hash[String, ValidationSupport::json_value]]
        invalid("$.payload.symbols", "must not be empty") if symbols.empty?
        names = [] #: Array[String]
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

      # @rbs (ValidationSupport::json_value data, Array[Hash[String, ValidationSupport::json_value]] symbols) -> void
      def validate_tokens(data, symbols)
        tokens = array(data, "$.payload.tokens") #: Array[Hash[String, ValidationSupport::json_value]]
        expected = symbols.select { |symbol| symbol.fetch("kind") == "terminal" }.map do |symbol|
          symbol.slice("id", "name", "display_name")
        end
        tokens.each_with_index do |token, index|
          record(token, "$.payload.tokens[#{index}]", %w[id name display_name])
        end
        invalid("$.payload.tokens", "must exactly index terminal symbols") unless tokens == expected
        token_id = tokens.first&.fetch("id")
        invalid("$.payload.tokens", "token id 0 must be $eof") unless token_id.is_a?(Integer) && token_id.zero? &&
                                                                      tokens.first.fetch("name") == "$eof"
      end

      # @rbs (ValidationSupport::json_value data,
      #   Array[Hash[String, ValidationSupport::json_value]] symbols, Integer state_count) -> void
      def validate_entries(data, symbols, state_count)
        entries = array(data, "$.payload.entry_states") #: Array[Hash[String, ValidationSupport::json_value]]
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

      # @rbs (ValidationSupport::json_value data,
      #   Array[Hash[String, ValidationSupport::json_value]] symbols) -> Array[Hash[String, ValidationSupport::json_value]]
      def validate_productions(data, symbols)
        productions = array(data, "$.payload.productions") #: Array[Hash[String, ValidationSupport::json_value]]
        nonterminals = symbol_ids(symbols, "nonterminal")
        productions.each_with_index do |production, index|
          path = "$.payload.productions[#{index}]"
          record(production, path, %w[id lhs rhs rhs_length action_slot])
          invalid("#{path}.id", "must be contiguous and ordered") unless production.fetch("id") == index
          lhs = integer(production.fetch("lhs"), "#{path}.lhs", minimum: 0)
          invalid("#{path}.lhs", "must reference a nonterminal") unless nonterminals.include?(lhs)
          rhs = array(production.fetch("rhs"), "#{path}.rhs")
          rhs.each_with_index do |symbol_id, rhs_index|
            symbol_id = integer(symbol_id, "#{path}.rhs[#{rhs_index}]", minimum: 0)
            invalid("#{path}.rhs[#{rhs_index}]", "references a missing symbol") unless symbol_id < symbols.length
          end
          invalid("#{path}.rhs_length", "must match rhs") unless production.fetch("rhs_length") == rhs.length
          slot = nullable_integer(production.fetch("action_slot"), "#{path}.action_slot", minimum: 0)
          invalid("#{path}.action_slot", "must equal production id") if slot && slot != index
        end
        productions
      end

      # @rbs (ValidationSupport::json_value data, Hash[String, ValidationSupport::json_value] payload) -> void
      def validate_cost(data, payload)
        path = "$.cost"
        keys = %w[
          canonical_payload_bytes action_cells goto_cells lookup_cost recognition_cost measurement bounded_by_max_steps
        ]
        data = record(data, path, keys)
        bytes = integer(data.fetch("canonical_payload_bytes"), "#{path}.canonical_payload_bytes", minimum: 1)
        unless bytes == Serializer.compact(payload).bytesize
          invalid("#{path}.canonical_payload_bytes",
                  "does not match payload")
        end
        action_cells = integer(data.fetch("action_cells"), "#{path}.action_cells", minimum: 0)
        goto_cells = integer(data.fetch("goto_cells"), "#{path}.goto_cells", minimum: 0)
        tables = payload.fetch("tables") #: Hash[String, ValidationSupport::json_value]
        actions = tables.fetch("actions") #: Hash[String, ValidationSupport::json_value]
        gotos = tables.fetch("gotos") #: Hash[String, ValidationSupport::json_value]
        invalid("#{path}.action_cells", "does not match actions") unless action_cells == occupied(actions, "codes")
        invalid("#{path}.goto_cells", "does not match gotos") unless goto_cells == occupied(gotos, "values")
        expected_lookup, expected_recognition = expected_costs(payload)
        invalid("#{path}.lookup_cost", "does not match table representation") unless
          data.fetch("lookup_cost") == expected_lookup
        invalid("#{path}.recognition_cost", "does not match table representation") unless
          data.fetch("recognition_cost") == expected_recognition
        enum(data.fetch("measurement"), "#{path}.measurement", ["not-measured"])
        invalid("#{path}.bounded_by_max_steps", "must be true") unless boolean(data.fetch("bounded_by_max_steps"),
                                                                               "#{path}.bounded_by_max_steps")
      end

      # @rbs (Hash[String, ValidationSupport::json_value] payload) -> [String, String]
      def expected_costs(payload)
        table_format = payload.fetch("table_format") #: Hash[String, ValidationSupport::json_value]
        compact = table_format.fetch("representation") == "compact"
        lookup = compact ? "O(1) row-displacement probe" : "O(log row width) binary search"
        recognition = if compact
                        "O(input tokens + reductions)"
                      else
                        "O((input tokens + reductions) * log maximum row width)"
                      end
        [lookup, "#{recognition}; lexer, recovery search, and semantic actions excluded"]
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table, String values_key) -> Integer
      def occupied(table, values_key)
        if table.key?("rows")
          rows = table.fetch("rows") #: Array[Array[ValidationSupport::json_value]]
          return rows.sum(&:length)
        end

        values = table.fetch(values_key) #: Array[ValidationSupport::json_value]
        values.compact.length
      end

      # @rbs (Array[Hash[String, ValidationSupport::json_value]] symbols, String kind) -> Set[Integer]
      def symbol_ids(symbols, kind)
        symbols.filter_map do |symbol|
          next unless symbol.fetch("kind") == kind

          symbol.fetch("id") #: Integer
        end.to_set
      end

      # @rbs (Hash[String, ValidationSupport::json_value] identity,
      #   Hash[String, ValidationSupport::json_value] payload, String identity_name,
      #   String payload_name) -> void
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
