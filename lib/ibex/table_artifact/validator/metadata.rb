# frozen_string_literal: true

require_relative "../../configuration"

module Ibex
  module TableArtifact
    class MetadataValidator
      include ValidationSupport

      # @rbs (Hash[String, ValidationSupport::json_value] payload, symbols: Array[Hash[String, ValidationSupport::json_value]],
      #   productions: Array[Hash[String, ValidationSupport::json_value]]) -> void
      def initialize(payload, symbols:, productions:)
        @payload = payload
        @symbols = symbols
        @productions = productions
        @terminal_ids = ids_for_kind(symbols, "terminal")
        @nonterminal_ids = ids_for_kind(symbols, "nonterminal")
      end

      # @rbs () -> void
      def validate!
        validate_semantic_actions(@payload.fetch("semantic_actions"))
        validate_recovery(@payload.fetch("recovery"))
        validate_cst(@payload.fetch("cst"))
      end

      private

      # @rbs (Array[Hash[String, ValidationSupport::json_value]] symbols, String kind) -> Set[Integer]
      def ids_for_kind(symbols, kind)
        symbols.filter_map do |symbol|
          next unless symbol.fetch("kind") == kind

          symbol.fetch("id") #: Integer
        end.to_set
      end

      # @rbs (ValidationSupport::json_value data) -> void
      def validate_semantic_actions(data)
        path = "$.payload.semantic_actions"
        data = record(data, path, %w[binding verified slots])
        enum(data.fetch("binding"), "#{path}.binding", ["opaque-wrapper-production-id-v1"])
        invalid("#{path}.verified", "must be false") unless boolean(data.fetch("verified"), "#{path}.verified") == false
        slots = integer_ids(data.fetch("slots"), "#{path}.slots")
        expected = @productions.filter_map { |production| production.fetch("action_slot") }
        invalid("#{path}.slots", "must match production action slots") unless slots == expected
      end

      # @rbs (ValidationSupport::json_value data) -> void
      def validate_recovery(data)
        path = "$.payload.recovery"
        data = record(data, path, %w[sync_token_ids on_error_reduce_symbol_ids])
        sync_ids = integer_ids(data.fetch("sync_token_ids"), "#{path}.sync_token_ids", sorted: false)
        sync_ids.each do |id|
          invalid("#{path}.sync_token_ids", "must reference terminals") unless @terminal_ids.include?(id)
        end
        groups = array(data.fetch("on_error_reduce_symbol_ids"), "#{path}.on_error_reduce_symbol_ids")
        groups.each_with_index do |group, index|
          ids = integer_ids(group, "#{path}.on_error_reduce_symbol_ids[#{index}]", sorted: false)
          invalid("#{path}.on_error_reduce_symbol_ids[#{index}]", "must not be empty") if ids.empty?
          ids.each do |id|
            invalid("#{path}.on_error_reduce_symbol_ids[#{index}]", "must reference nonterminals") unless
              @nonterminal_ids.include?(id)
          end
        end
      end

      # @rbs (ValidationSupport::json_value data) -> void
      def validate_cst(data)
        return if data.nil?

        path = "$.payload.cst"
        data = record(data, path, %w[version trivia_policy kinds slots])
        invalid("#{path}.version", "must be 1") unless integer(data.fetch("version"), "#{path}.version") == 1
        enum(
          data.fetch("trivia_policy"), "#{path}.trivia_policy",
          Configuration::Registry.parser_setting_values(:cst_trivia).map(&:to_s)
        )
        kind_count = validate_cst_kinds(data.fetch("kinds"), "#{path}.kinds")
        validate_cst_slots(data.fetch("slots"), "#{path}.slots", kind_count)
      end

      # @rbs (ValidationSupport::json_value data, String path) -> Integer
      def validate_cst_kinds(data, path)
        keys = %w[names terminal_range nonterminal_range named named_nonterminals trivia synthetic]
        data = record(data, path, keys)
        names = array(data.fetch("names"), "#{path}.names") #: Array[String]
        names.each_with_index { |name, index| string(name, "#{path}.names[#{index}]") }
        validate_range(data.fetch("terminal_range"), "#{path}.terminal_range", names.length)
        validate_range(data.fetch("nonterminal_range"), "#{path}.nonterminal_range", names.length)
        %w[named trivia synthetic].each { |key| validate_named_kinds(data.fetch(key), "#{path}.#{key}", names) }
        validate_named_nonterminals(data.fetch("named_nonterminals"), "#{path}.named_nonterminals", names.length)
        names.length
      end

      # @rbs (ValidationSupport::json_value data, String path, Integer limit) -> void
      def validate_range(data, path, limit)
        values = array(data, path)
        invalid(path, "must contain two bounds") unless values.length == 2
        start = integer(values.fetch(0), "#{path}[0]", minimum: 0)
        finish = integer(values.fetch(1), "#{path}[1]", minimum: 0)
        invalid(path, "must be an ordered half-open range") unless finish.between?(start, limit)
      end

      # @rbs (ValidationSupport::json_value data, String path, Array[String] names) -> void
      def validate_named_kinds(data, path, names)
        entries = array(data, path)
        ids = entries.map.with_index do |entry, index|
          entry_path = "#{path}[#{index}]"
          entry = record(entry, entry_path, %w[name id])
          name = string(entry.fetch("name"), "#{entry_path}.name")
          id = integer(entry.fetch("id"), "#{entry_path}.id", minimum: 0)
          invalid(entry_path, "does not match the kind name table") unless names[id] == name
          id
        end
        sorted_unique!(ids, path)
      end

      # @rbs (ValidationSupport::json_value data, String path, Integer kind_count) -> void
      def validate_named_nonterminals(data, path, kind_count)
        pairs = array(data, path).map.with_index do |entry, index|
          entry_path = "#{path}[#{index}]"
          entry = record(entry, entry_path, %w[kind_id symbol_id])
          kind_id = integer(entry.fetch("kind_id"), "#{entry_path}.kind_id", minimum: 0)
          invalid("#{entry_path}.kind_id", "references a missing kind") unless kind_id < kind_count
          symbol_id = integer(entry.fetch("symbol_id"), "#{entry_path}.symbol_id", minimum: 0)
          invalid("#{entry_path}.symbol_id", "must reference a nonterminal") unless @nonterminal_ids.include?(symbol_id)
          [kind_id, symbol_id]
        end
        return if pairs == pairs.sort && pairs.map(&:first).uniq.length == pairs.length

        invalid(path,
                "must be sorted with unique kind ids")
      end

      # @rbs (ValidationSupport::json_value data, String path, Integer kind_count) -> void
      def validate_cst_slots(data, path, kind_count)
        production_ids = array(data, path).map.with_index do |slot, index|
          slot_path = "#{path}[#{index}]"
          slot = record(slot, slot_path, %w[production_id node_kind_id node_name fields])
          production_id = integer(slot.fetch("production_id"), "#{slot_path}.production_id", minimum: 0)
          unless production_id < @productions.length
            invalid("#{slot_path}.production_id",
                    "references a missing production")
          end
          node_kind = integer(slot.fetch("node_kind_id"), "#{slot_path}.node_kind_id", minimum: 0)
          invalid("#{slot_path}.node_kind_id", "references a missing kind") unless node_kind < kind_count
          string(slot.fetch("node_name"), "#{slot_path}.node_name")
          validate_fields(slot.fetch("fields"), "#{slot_path}.fields", @productions.fetch(production_id))
          production_id
        end
        sorted_unique!(production_ids, path)
      end

      # @rbs (ValidationSupport::json_value data, String path,
      #   Hash[String, ValidationSupport::json_value] production) -> void
      def validate_fields(data, path, production)
        names = array(data, path).map.with_index do |field, index|
          field_path = "#{path}[#{index}]"
          field = record(field, field_path, %w[name index extraction])
          name = string(field.fetch("name"), "#{field_path}.name")
          field_index = integer(field.fetch("index"), "#{field_path}.index", minimum: 0)
          rhs_length = production.fetch("rhs_length") #: Integer
          invalid("#{field_path}.index", "exceeds production rhs") unless field_index < rhs_length
          extraction = field.fetch("extraction")
          enum(extraction, "#{field_path}.extraction", %w[repetition separated_list]) unless extraction.nil?
          name
        end
        invalid(path, "must have unique field names") unless names.uniq.length == names.length
      end

      # @rbs (ValidationSupport::json_value data, String path, ?sorted: bool) -> Array[Integer]
      def integer_ids(data, path, sorted: true)
        ids = array(data, path).map.with_index { |id, index| integer(id, "#{path}[#{index}]", minimum: 0) }
        if sorted
          sorted_unique!(ids, path)
        else
          invalid(path, "must contain unique ids") unless ids.uniq.length == ids.length
        end
        ids
      end
    end
  end
end
