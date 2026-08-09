# frozen_string_literal: true

module Ibex
  module TableArtifact
    # Recognition-only driver over internal token ids; it never loads wrapper code.
    class Executor
      class Result
        attr_reader :status #: Symbol
        attr_reader :steps #: Integer
        attr_reader :consumed_tokens #: Integer
        attr_reader :reason #: String?

        # @rbs (status: Symbol, steps: Integer, consumed_tokens: Integer, reason: String?) -> void
        def initialize(status:, steps:, consumed_tokens:, reason:)
          @status = status
          @steps = steps
          @consumed_tokens = consumed_tokens
          @reason = reason
          freeze
        end

        # @rbs () -> bool
        def accepted? = status == :accepted
        # @rbs () -> bool
        def rejected? = status == :rejected
        # @rbs () -> bool
        def exhausted? = status == :exhausted
      end

      # @rbs (Document | Hash[String, ValidationSupport::json_value] document) -> void
      def initialize(document)
        @payload = document.is_a?(Document) ? document.payload : Document.new(document).payload
        @tables = @payload.fetch("tables") #: Hash[String, ValidationSupport::json_value]
        @productions = @payload.fetch("productions") #: Array[Hash[String, ValidationSupport::json_value]]
        tokens = @payload.fetch("tokens") #: Array[Hash[String, ValidationSupport::json_value]]
        @terminal_ids = tokens.map do |token|
          token.fetch("id") #: Integer
        end
      end

      # @rbs (Array[Integer] token_ids, ?entry: String | Symbol?, ?max_steps: Integer) -> Result
      def recognize(token_ids, entry: nil, max_steps: 1_000_000)
        raise ArgumentError, "max_steps must be positive" unless max_steps.is_a?(Integer) && max_steps.positive?

        input = validate_input(token_ids)
        input << 0 unless input.last&.zero?
        stack = [entry_state(entry)]
        execute(input, stack, max_steps)
      end

      private

      # @rbs (Array[Integer] input, Array[Integer] stack, Integer max_steps) -> Result
      def execute(input, stack, max_steps)
        cursor = 0
        max_steps.times do |step|
          return result(:rejected, step + 1, cursor, "parser shifted past end of input") if cursor >= input.length

          code = action(stack.last, input.fetch(cursor))
          immediate = immediate_result(code, input.fetch(cursor), step, cursor)
          return immediate if immediate

          code ||= -1
          if code.positive?
            stack << (code - 1)
            cursor += 1
            next
          end

          reason = reduce_stack(stack, code)
          return result(:rejected, step + 1, cursor, reason) if reason
        end
        result(:exhausted, max_steps, cursor, "max_steps exceeded")
      end

      # @rbs (Integer? code, Integer token_id, Integer step, Integer cursor) -> Result?
      def immediate_result(code, token_id, step, cursor)
        return result(:rejected, step + 1, cursor, "no parser action") if code.nil? || code == -1
        return unless code.zero?
        return result(:rejected, step + 1, cursor, "accept action before end of input") unless token_id.zero?

        result(:accepted, step + 1, cursor, nil)
      end

      # @rbs (Array[Integer] token_ids) -> Array[Integer]
      def validate_input(token_ids)
        raise ArgumentError, "token_ids must be an array" unless token_ids.is_a?(Array)

        token_ids.map.with_index do |token_id, index|
          raise ArgumentError, "token_ids[#{index}] must be an internal terminal id" unless
            token_id.is_a?(Integer) && @terminal_ids.include?(token_id)
          raise ArgumentError, "$eof may only appear at the end" if token_id.zero? && index != token_ids.length - 1

          token_id
        end
      end

      # @rbs (String | Symbol? requested) -> Integer
      def entry_state(requested)
        entries = @payload.fetch("entry_states") #: Array[Hash[String, ValidationSupport::json_value]]
        default_state = entries.first.fetch("state") #: Integer
        return default_state unless requested

        entry = entries.find { |candidate| candidate.fetch("name") == requested.to_s }
        raise ArgumentError, "unknown parser entry #{requested.inspect}" unless entry

        entry.fetch("state") #: Integer
      end

      # @rbs (Integer row, Integer column) -> Integer?
      def action(row, column)
        table = @tables.fetch("actions") #: Hash[String, ValidationSupport::json_value]
        code = if table.fetch("encoding") == "signed-sparse-rows-v1"
                 rows = table.fetch("rows") #: Array[Array[Hash[String, ValidationSupport::json_value]]]
                 cells = rows.fetch(row)
                 cells.bsearch do |cell|
                   token_id = cell.fetch("token_id") #: Integer
                   token_id >= column
                 end&.then do |cell|
                   token_id = cell.fetch("token_id") #: Integer
                   if token_id == column
                     cell.fetch("code") #: Integer
                   end
                 end
               else
                 displacement_lookup(table, row, column, "codes")
               end
        defaults = @tables.fetch("default_actions") #: Array[Integer?]
        code.nil? ? defaults.fetch(row) : code
      end

      # @rbs (Integer row, Integer column) -> Integer?
      def goto_state(row, column)
        table = @tables.fetch("gotos") #: Hash[String, ValidationSupport::json_value]
        if table.fetch("encoding") == "sparse-rows-v1"
          rows = table.fetch("rows") #: Array[Array[Hash[String, ValidationSupport::json_value]]]
          cells = rows.fetch(row)
          cells.bsearch do |cell|
            symbol_id = cell.fetch("symbol_id") #: Integer
            symbol_id >= column
          end&.then do |cell|
            symbol_id = cell.fetch("symbol_id") #: Integer
            if symbol_id == column
              cell.fetch("state") #: Integer
            end
          end
        else
          displacement_lookup(table, row, column, "values")
        end
      end

      # @rbs (Hash[String, ValidationSupport::json_value] table, Integer row, Integer column, String value_key) -> Integer?
      def displacement_lookup(table, row, column, value_key)
        offsets = table.fetch("offsets") #: Array[Integer]
        index = offsets.fetch(row) + column
        checks = table.fetch("checks") #: Array[Integer?]
        return if index.negative? || index >= checks.length || checks[index] != row

        values = table.fetch(value_key) #: Array[Integer?]
        values.fetch(index)
      end

      # @rbs (Array[Integer] stack, Integer code) -> String?
      def reduce_stack(stack, code)
        production = @productions.fetch(-2 - code)
        length = production.fetch("rhs_length") #: Integer
        return "reduction underflow" if length >= stack.length

        stack.pop(length)
        lhs = production.fetch("lhs") #: Integer
        state = goto_state(stack.last, lhs)
        return "missing goto after reduction" unless state

        stack << state
        nil
      end

      # @rbs (Symbol status, Integer steps, Integer consumed, String? reason) -> Result
      def result(status, steps, consumed, reason)
        Result.new(status: status, steps: steps, consumed_tokens: consumed, reason: reason)
      end
    end
  end
end
