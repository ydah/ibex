# frozen_string_literal: true

module Ibex
  module TableArtifact
    # Recognition-only driver over internal token ids; it never loads wrapper code.
    class Executor
      Result = Struct.new(:status, :steps, :consumed_tokens, :reason, keyword_init: true) do
        def accepted? = status == :accepted
        def rejected? = status == :rejected
        def exhausted? = status == :exhausted
      end

      def initialize(document)
        @payload = document.is_a?(Document) ? document.payload : Document.new(document).payload
        @tables = @payload.fetch("tables")
        @productions = @payload.fetch("productions")
        @terminal_ids = @payload.fetch("tokens").map { |token| token.fetch("id") }
      end

      def recognize(token_ids, entry: nil, max_steps: 1_000_000)
        raise ArgumentError, "max_steps must be positive" unless max_steps.positive?

        input = validate_input(token_ids)
        input << 0 unless input.last.zero?
        stack = [entry_state(entry)]
        cursor = 0
        max_steps.times do |step|
          code = action(stack.last, input.fetch(cursor))
          return result(:rejected, step + 1, cursor, "no parser action") if code.nil? || code == -1
          return result(:accepted, step + 1, cursor, nil) if code.zero?

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

      private

      def validate_input(token_ids)
        raise ArgumentError, "token_ids must be an array" unless token_ids.is_a?(Array)

        token_ids.map.with_index do |token_id, index|
          raise ArgumentError, "token_ids[#{index}] must be an internal terminal id" unless
            token_id.is_a?(Integer) && @terminal_ids.include?(token_id)
          raise ArgumentError, "$eof may only appear at the end" if token_id.zero? && index != token_ids.length - 1

          token_id
        end
      end

      def entry_state(requested)
        entries = @payload.fetch("entry_states")
        return entries.first.fetch("state") unless requested

        entry = entries.find { |candidate| candidate.fetch("name") == requested.to_s }
        raise ArgumentError, "unknown parser entry #{requested.inspect}" unless entry

        entry.fetch("state")
      end

      def action(row, column)
        table = @tables.fetch("actions")
        code = if table.fetch("encoding") == "signed-sparse-rows-v1"
                 table.fetch("rows").fetch(row).bsearch { |cell| cell.fetch("token_id") >= column }
                                               &.then do |cell|
                   cell.fetch("code") if cell.fetch("token_id") == column
                 end
               else
                 displacement_lookup(table, row, column, "codes")
               end
        code.nil? ? @tables.fetch("default_actions").fetch(row) : code
      end

      def goto_state(row, column)
        table = @tables.fetch("gotos")
        if table.fetch("encoding") == "sparse-rows-v1"
          table.fetch("rows").fetch(row).bsearch { |cell| cell.fetch("symbol_id") >= column }
                                        &.then do |cell|
            cell.fetch("state") if cell.fetch("symbol_id") == column
          end
        else
          displacement_lookup(table, row, column, "values")
        end
      end

      def displacement_lookup(table, row, column, value_key)
        index = table.fetch("offsets").fetch(row) + column
        checks = table.fetch("checks")
        return if index.negative? || index >= checks.length || checks[index] != row

        table.fetch(value_key).fetch(index)
      end

      def reduce_stack(stack, code)
        production = @productions.fetch(-2 - code)
        length = production.fetch("rhs_length")
        return "reduction underflow" if length >= stack.length

        stack.pop(length)
        state = goto_state(stack.last, production.fetch("lhs"))
        return "missing goto after reduction" unless state

        stack << state
        nil
      end

      def result(status, steps, consumed, reason)
        Result.new(status: status, steps: steps, consumed_tokens: consumed, reason: reason).freeze
      end
    end
  end
end
