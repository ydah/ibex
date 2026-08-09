# frozen_string_literal: true

module Ibex
  module TableArtifact
    # Projects validated Automaton IR into an action-free executable sidecar.
    class Builder
      # @rbs!
      #   type json_value = String | Integer | bool | nil | Array[json_value] | Hash[String, json_value]
      #   type json_hash = Hash[String, json_value]
      #   type action_rows = Array[Hash[Integer, IR::runtime_action]]
      #   type action_table = action_rows | Tables::CompactActions
      #   type goto_rows = Array[Hash[Integer, Integer]]
      #   type goto_table = goto_rows | Tables::Compact

      include CSTProjection

      REPRESENTATIONS = %i[plain compact].freeze #: Array[Symbol]

      # @rbs (IR::Automaton automaton, ?representation: Symbol | String, ?cst_trivia: Symbol | String?,
      #   ?omit_action_call: bool?) -> void
      def initialize(automaton, representation: :compact, cst_trivia: nil, omit_action_call: nil)
        @automaton = automaton
        @grammar = automaton.grammar
        @representation = representation.to_sym
        @cst_trivia = effective_cst_trivia(cst_trivia)
        @omit_action_call = omit_action_call.nil? ? @grammar.options.fetch(:omit_action_call) : omit_action_call
        return if REPRESENTATIONS.include?(@representation)

        raise ArgumentError, "representation must be :plain or :compact"
      end

      # @rbs () -> Document
      def build
        source_identity = {
          "grammar_digest" => @automaton.grammar_digest,
          "automaton_digest" => automaton_digest
        }
        payload = build_payload(source_identity)
        cost = build_cost(payload)
        identity = source_identity.merge(
          "payload_digest" => Serializer.digest(payload),
          "cst_metadata_digest" => Serializer.digest(payload.fetch("cst")),
          "recovery_metadata_digest" => Serializer.digest(payload.fetch("recovery"))
        )
        Document.new(
          "artifact_type" => ARTIFACT_TYPE,
          "schema_version" => SCHEMA_VERSION,
          "identity" => identity,
          "payload" => payload,
          "cost" => cost
        )
      end

      private

      # @rbs (Hash[String, String] source_identity) -> json_hash
      def build_payload(source_identity)
        {
          "table_format" => table_format,
          "source" => source_identity,
          "state_count" => @automaton.states.length,
          "symbols" => symbols,
          "tokens" => tokens,
          "entry_states" => entry_states,
          "tables" => tables,
          "productions" => productions,
          "cst" => cst,
          "recovery" => recovery,
          "semantic_actions" => semantic_actions
        }
      end

      # @rbs () -> String
      def automaton_digest
        "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(@automaton))}"
      end

      # @rbs () -> json_hash
      def table_format
        {
          "family" => "ibex-runtime-parser-table",
          "version" => Runtime::PARSER_TABLE_FORMAT_VERSION,
          "representation" => @representation.to_s,
          "action_encoding" => @representation == :compact ? "signed-row-displacement-v1" : "signed-sparse-rows-v1",
          "goto_encoding" => @representation == :compact ? "row-displacement-v1" : "sparse-rows-v1"
        }
      end

      # @rbs () -> Array[json_hash]
      def symbols
        @grammar.symbols.sort_by(&:id).map do |symbol|
          {
            "id" => symbol.id,
            "name" => symbol.name,
            "kind" => symbol.kind.to_s,
            "display_name" => symbol.display_name
          }
        end
      end

      # @rbs () -> Array[json_hash]
      def tokens
        @grammar.terminals.sort_by(&:id).map do |symbol|
          { "id" => symbol.id, "name" => symbol.name, "display_name" => symbol.display_name }
        end
      end

      # @rbs () -> Array[json_hash]
      def entry_states
        @automaton.entry_states.map { |name, state| { "name" => name, "state" => state } }
      end

      # @rbs () -> json_hash
      def tables
        table_set = Tables.build(@automaton, format: @representation) #: Tables::TableSet
        {
          "actions" => action_table(table_set.actions),
          "gotos" => goto_table(table_set.gotos),
          "default_actions" => table_set.default_actions.map { |action| Tables::CompactActions.pack(action) }
        }
      end

      # @rbs (action_table table) -> json_hash
      def action_table(table)
        return compact_action_table(table) if table.is_a?(Tables::CompactActions)

        {
          "encoding" => "signed-sparse-rows-v1",
          "rows" => table.map do |row|
            row.sort.map { |token_id, action| { "token_id" => token_id, "code" => Tables::CompactActions.pack(action) } }
          end
        }
      end

      # @rbs (Tables::CompactActions table) -> json_hash
      def compact_action_table(table)
        {
          "encoding" => "signed-row-displacement-v1",
          "row_count" => table.row_count,
          "column_count" => table.column_count,
          "offsets" => table.offsets,
          "codes" => table.codes,
          "checks" => table.checks
        }
      end

      # @rbs (goto_table table) -> json_hash
      def goto_table(table)
        return compact_goto_table(table) if table.is_a?(Tables::Compact)

        {
          "encoding" => "sparse-rows-v1",
          "rows" => table.map do |row|
            row.sort.map { |symbol_id, state| { "symbol_id" => symbol_id, "state" => state } }
          end
        }
      end

      # @rbs (Tables::Compact table) -> json_hash
      def compact_goto_table(table)
        {
          "encoding" => "row-displacement-v1",
          "row_count" => table.row_count,
          "dense_width" => table.dense_width,
          "offsets" => table.offsets,
          "values" => table.values,
          "checks" => table.checks
        }
      end

      # @rbs () -> Array[json_hash]
      def productions
        @grammar.productions.sort_by(&:id).map do |production|
          {
            "id" => production.id,
            "lhs" => production.lhs,
            "rhs" => production.rhs,
            "rhs_length" => production.rhs.length,
            "action_slot" => action_slot?(production) ? production.id : nil
          }
        end
      end

      # @rbs (IR::Production production) -> bool
      def action_slot?(production)
        !!(production.node || production.action || !@omit_action_call)
      end

      # @rbs () -> json_hash
      def semantic_actions
        {
          "binding" => "opaque-wrapper-production-id-v1",
          "verified" => false,
          "slots" => @grammar.productions.select { |production| action_slot?(production) }.map(&:id)
        }
      end

      # @rbs () -> json_hash
      def recovery
        sync_tokens = @grammar.recovery.fetch(:sync_tokens) #: Array[String]
        on_error_reduce = @grammar.recovery.fetch(:on_error_reduce) #: Array[Array[String]]
        {
          "sync_token_ids" => sync_tokens.map { |name| @grammar.symbol(name).id },
          "on_error_reduce_symbol_ids" => on_error_reduce.map do |group|
            group.map { |name| @grammar.symbol(name).id }
          end
        }
      end

      # @rbs (json_hash payload) -> json_hash
      def build_cost(payload)
        tables = payload.fetch("tables") #: json_hash
        action_table = tables.fetch("actions") #: json_hash
        goto_table = tables.fetch("gotos") #: json_hash
        {
          "canonical_payload_bytes" => Serializer.compact(payload).bytesize,
          "action_cells" => occupied_cells(action_table, "codes"),
          "goto_cells" => occupied_cells(goto_table, "values"),
          "lookup_cost" => lookup_cost,
          "recognition_cost" => recognition_cost,
          "measurement" => "not-measured",
          "bounded_by_max_steps" => true
        }
      end

      # @rbs (json_hash table, String values_key) -> Integer
      def occupied_cells(table, values_key)
        rows = table.fetch("rows") #: Array[json_value]
        return rows.sum { |row| row.is_a?(Array) ? row.length : 0 } if table.key?("rows")

        values = table.fetch(values_key) #: Array[json_value]
        values.compact.length
      end

      # @rbs () -> String
      def lookup_cost
        return "O(1) row-displacement probe" if @representation == :compact

        "O(log row width) binary search"
      end

      # @rbs () -> String
      def recognition_cost
        prefix = if @representation == :compact
                   "O(input tokens + reductions)"
                 else
                   "O((input tokens + reductions) * log maximum row width)"
                 end
        "#{prefix}; lexer, recovery search, and semantic actions excluded"
      end

      # @rbs (Symbol | String? requested) -> Symbol
      def effective_cst_trivia(requested)
        contract_entry = @grammar.parser_contract&.cst_trivia
        persisted = contract_entry.value if contract_entry&.explicit
        if requested && persisted && requested.to_sym != persisted
          raise ArgumentError, "cst_trivia conflicts with the persisted parser contract"
        end

        (requested || persisted || :leading).to_sym
      end
    end
  end
end
