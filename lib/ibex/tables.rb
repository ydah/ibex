# frozen_string_literal: true

module Ibex
  # Parser table construction and row-displacement compression.
  module Tables
    TableSet = Struct.new(:actions, :gotos, keyword_init: true)

    # Sparse table represented by per-row offsets and ownership checks.
    class Compact
      attr_reader :offsets, :values, :checks, :row_count

      def self.build(rows)
        offsets = Array.new(rows.length, 0)
        values = []
        checks = []
        rows.each_index.sort_by { |row| [-rows[row].length, row] }.each do |row|
          offset = find_offset(rows[row].keys, checks)
          offsets[row] = offset
          rows[row].each do |column, value|
            index = offset + column
            values[index] = value
            checks[index] = row
          end
        end
        new(offsets: offsets, values: values, checks: checks, row_count: rows.length)
      end

      def self.find_offset(columns, checks)
        offset = 0
        offset += 1 while columns.any? { |column| checks[offset + column] }
        offset
      end
      private_class_method :find_offset

      def initialize(offsets:, values:, checks:, row_count:)
        @offsets = offsets.freeze
        @values = values.freeze
        @checks = checks.freeze
        @row_count = row_count
        freeze
      end

      def lookup(row, column)
        return nil unless row.between?(0, @row_count - 1)

        index = @offsets.fetch(row) + column
        @checks[index] == row ? @values[index] : nil
      end

      def row(row)
        return {} unless row.between?(0, @row_count - 1)

        result = {}
        @checks.each_index do |index|
          next unless @checks[index] == row

          result[index - @offsets[row]] = @values[index]
        end
        result
      end
    end

    module_function

    def build(automaton, format: :compact)
      action_rows = automaton.states.map { |state| state.actions.transform_values { |action| runtime_action(action) } }
      goto_rows = automaton.states.map(&:gotos)
      return TableSet.new(actions: action_rows, gotos: goto_rows) if format.to_sym == :plain
      raise ArgumentError, "unknown table format #{format.inspect}" unless format.to_sym == :compact

      TableSet.new(actions: Compact.build(action_rows), gotos: Compact.build(goto_rows))
    end

    def runtime_action(action)
      case action.fetch(:type).to_sym
      when :shift then [:shift, action.fetch(:state)]
      when :reduce then [:reduce, action.fetch(:production)]
      when :accept then [:accept]
      when :error then [:error]
      end
    end
    private_class_method :runtime_action
  end
end
