# frozen_string_literal: true

module Ibex
  module TableArtifact
    class TableValidator
      include ValidationSupport

      # @rbs!
      #   private def integer_array: (ValidationSupport::json_value value, String path,
      #     allow_nil: false, minimum: Integer?) -> Array[Integer]
      #                            | (ValidationSupport::json_value value, String path,
      #     allow_nil: true, minimum: Integer?) -> Array[Integer?]

      # @rbs (Hash[String, ValidationSupport::json_value] data, state_count: Integer, production_count: Integer,
      #   terminal_ids: Set[Integer], nonterminal_ids: Set[Integer], representation: String) -> void
      def initialize(data, state_count:, production_count:, terminal_ids:, nonterminal_ids:, representation:)
        @data = data
        @state_count = state_count
        @production_count = production_count
        @terminal_ids = terminal_ids
        @nonterminal_ids = nonterminal_ids
        @representation = representation
      end

      # @rbs () -> void
      def validate!
        record(@data, "$.payload.tables", %w[actions gotos default_actions])
        validate_actions(@data.fetch("actions"))
        validate_gotos(@data.fetch("gotos"))
        validate_defaults(@data.fetch("default_actions"))
      end

      private

      # @rbs (ValidationSupport::json_value table) -> void
      def validate_actions(table)
        invalid("$.payload.tables.actions", "must be an object") unless table.is_a?(Hash)
        table_data = table #: Hash[String, ValidationSupport::json_value]
        encoding = table_data["encoding"]
        expected = @representation == "compact" ? "signed-row-displacement-v1" : "signed-sparse-rows-v1"
        invalid("$.payload.tables.actions.encoding", "does not match table representation") unless encoding == expected
        case encoding
        when "signed-sparse-rows-v1" then validate_sparse_actions(table_data)
        when "signed-row-displacement-v1" then validate_compact_actions(table_data)
        else invalid("$.payload.tables.actions.encoding", "is unsupported")
        end
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table) -> void
      def validate_sparse_actions(table)
        record(table, "$.payload.tables.actions", %w[encoding rows])
        rows = array(table.fetch("rows"), "$.payload.tables.actions.rows")
        invalid("$.payload.tables.actions.rows", "must contain one row per state") unless rows.length == @state_count
        rows.each_with_index do |row, state|
          token_ids = array(row, "$.payload.tables.actions.rows[#{state}]").map.with_index do |cell, index|
            path = "$.payload.tables.actions.rows[#{state}][#{index}]"
            cell = record(cell, path, %w[token_id code])
            token_id = integer(cell.fetch("token_id"), "#{path}.token_id", minimum: 0)
            invalid("#{path}.token_id", "must reference a terminal") unless @terminal_ids.include?(token_id)
            validate_token_action(cell.fetch("code"), token_id, "#{path}.code")
            token_id
          end
          sorted_unique!(token_ids, "$.payload.tables.actions.rows[#{state}]")
        end
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table) -> void
      def validate_compact_actions(table)
        keys = %w[encoding row_count column_count offsets codes checks]
        record(table, "$.payload.tables.actions", keys)
        enum(table.fetch("encoding"), "$.payload.tables.actions.encoding", ["signed-row-displacement-v1"])
        validate_row_count(table, "$.payload.tables.actions")
        column_count = nullable_integer(table.fetch("column_count"), "$.payload.tables.actions.column_count",
                                        minimum: 1)
        rows = validate_displacement(table, value_key: "codes", path: "$.payload.tables.actions") do |column, code,
                                                                                                         cell_path|
          invalid(cell_path, "column must reference a terminal") unless @terminal_ids.include?(column)
          invalid(cell_path, "column exceeds column_count") if column_count && column >= column_count
          validate_token_action(code, column, "#{cell_path}.code")
        end
        validate_canonical_displacement(
          table, rows, value_key: "codes", width_key: "column_count", width: column_count, dense: false,
                       path: "$.payload.tables.actions"
        )
      end

      # @rbs (ValidationSupport::json_value table) -> void
      def validate_gotos(table)
        invalid("$.payload.tables.gotos", "must be an object") unless table.is_a?(Hash)
        table_data = table #: Hash[String, ValidationSupport::json_value]
        encoding = table_data["encoding"]
        expected = @representation == "compact" ? "row-displacement-v1" : "sparse-rows-v1"
        invalid("$.payload.tables.gotos.encoding", "does not match table representation") unless encoding == expected
        case encoding
        when "sparse-rows-v1" then validate_sparse_gotos(table_data)
        when "row-displacement-v1" then validate_compact_gotos(table_data)
        else invalid("$.payload.tables.gotos.encoding", "is unsupported")
        end
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table) -> void
      def validate_sparse_gotos(table)
        record(table, "$.payload.tables.gotos", %w[encoding rows])
        rows = array(table.fetch("rows"), "$.payload.tables.gotos.rows")
        invalid("$.payload.tables.gotos.rows", "must contain one row per state") unless rows.length == @state_count
        rows.each_with_index do |row, state|
          symbol_ids = array(row, "$.payload.tables.gotos.rows[#{state}]").map.with_index do |cell, index|
            path = "$.payload.tables.gotos.rows[#{state}][#{index}]"
            cell = record(cell, path, %w[symbol_id state])
            symbol_id = integer(cell.fetch("symbol_id"), "#{path}.symbol_id", minimum: 0)
            invalid("#{path}.symbol_id", "must reference a nonterminal") unless @nonterminal_ids.include?(symbol_id)
            validate_state(cell.fetch("state"), "#{path}.state")
            symbol_id
          end
          sorted_unique!(symbol_ids, "$.payload.tables.gotos.rows[#{state}]")
        end
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table) -> void
      def validate_compact_gotos(table)
        keys = %w[encoding row_count dense_width offsets values checks]
        record(table, "$.payload.tables.gotos", keys)
        enum(table.fetch("encoding"), "$.payload.tables.gotos.encoding", ["row-displacement-v1"])
        validate_row_count(table, "$.payload.tables.gotos")
        dense_width = nullable_integer(table.fetch("dense_width"), "$.payload.tables.gotos.dense_width", minimum: 1)
        rows = validate_displacement(table, value_key: "values", path: "$.payload.tables.gotos") do |column, state,
                                                                                                         cell_path|
          invalid(cell_path, "column must reference a nonterminal") unless @nonterminal_ids.include?(column)
          invalid(cell_path, "column exceeds dense_width") if dense_width && column >= dense_width
          validate_state(state, "#{cell_path}.state")
        end
        validate_canonical_displacement(
          table, rows, value_key: "values", width_key: "dense_width", width: dense_width, dense: true,
                       path: "$.payload.tables.gotos"
        )
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table, String path) -> void
      def validate_row_count(table, path)
        count = integer(table.fetch("row_count"), "#{path}.row_count", minimum: 1)
        invalid("#{path}.row_count", "must equal state_count") unless count == @state_count
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table, value_key: String, path: String)
      #   { (Integer, ValidationSupport::json_value, String) -> void } -> Array[Hash[Integer, ValidationSupport::json_value]]
      def validate_displacement(table, value_key:, path:)
        offsets = integer_array(table.fetch("offsets"), "#{path}.offsets", allow_nil: false, minimum: 0)
        invalid("#{path}.offsets", "must contain one offset per state") unless offsets.length == @state_count
        minimum = value_key == "codes" ? nil : 0
        values = integer_array(table.fetch(value_key), "#{path}.#{value_key}", allow_nil: true, minimum: minimum)
        checks = integer_array(table.fetch("checks"), "#{path}.checks", allow_nil: true, minimum: 0)
        invalid(path, "#{value_key} and checks must have equal length") unless values.length == checks.length

        rows = Array.new(@state_count) { {} } #: Array[Hash[Integer, ValidationSupport::json_value]]
        checks.each_index do |index|
          row = checks[index]
          value = values[index]
          invalid("#{path}[#{index}]", "value and check occupancy must match") unless row.nil? == value.nil?
          next unless row

          invalid("#{path}.checks[#{index}]", "references a missing state") unless row.between?(0, @state_count - 1)
          column = index - offsets.fetch(row)
          invalid("#{path}[#{index}]", "has a negative column") if column.negative?
          yield(column, value, "#{path}[#{index}]")
          rows.fetch(row)[column] = value
        end
        rows
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table,
      #   Array[Hash[Integer, ValidationSupport::json_value]] rows, value_key: String,
      #   width_key: String, width: Integer?, dense: bool, path: String) -> void
      def validate_canonical_displacement(table, rows, value_key:, width_key:, width:, dense:, path:)
        canonical = Tables::Compact.build(rows, dense: dense)
        expected = [canonical.offsets, canonical.values, canonical.checks]
        actual = [table.fetch("offsets"), table.fetch(value_key), table.fetch("checks")]
        invalid(path, "must use the canonical minimal row-displacement layout") unless actual == expected

        expected_width = if width_key == "column_count"
                           rows.flat_map(&:keys).max.to_i + 1
                         else
                           canonical.dense_width
                         end
        expected_width = nil if expected_width && (@state_count * expected_width) > Tables::Compact::DENSE_CELL_LIMIT
        invalid("#{path}.#{width_key}", "does not match the canonical table width") unless width == expected_width
      end

      # @rbs skip
      def integer_array(value, path, allow_nil:, minimum:)
        array(value, path).map.with_index do |item, index|
          next if allow_nil && item.nil?

          integer(item, "#{path}[#{index}]", minimum: minimum)
        end
      end

      # @rbs (ValidationSupport::json_value defaults) -> void
      def validate_defaults(defaults)
        values = array(defaults, "$.payload.tables.default_actions")
        unless values.length == @state_count
          invalid("$.payload.tables.default_actions",
                  "must contain one entry per state")
        end
        values.each_with_index do |code, state|
          next if code.nil?

          path = "$.payload.tables.default_actions[#{state}]"
          code = integer(code, path)
          invalid(path, "must be an error or reduction") if code >= 0
        end
      end

      # @rbs (ValidationSupport::json_value code, Integer token_id, String path) -> void
      def validate_token_action(code, token_id, path)
        code = integer(code, path)
        invalid(path, "accept is only valid for $eof") if code.zero? && !token_id.zero?
        invalid(path, "$eof cannot be shifted") if token_id.zero? && code.positive?
        validate_action_code(code, path)
      end

      # @rbs (ValidationSupport::json_value code, String path) -> void
      def validate_action_code(code, path)
        code = integer(code, path)
        return if [0, -1].include?(code)
        return validate_state(code - 1, path) if code.positive?

        production = -2 - code
        invalid(path, "references a missing production") unless production.between?(0, @production_count - 1)
      end

      # @rbs (ValidationSupport::json_value state, String path) -> void
      def validate_state(state, path)
        state = integer(state, path, minimum: 0)
        invalid(path, "references a missing state") unless state.between?(0, @state_count - 1)
      end
    end
  end
end
