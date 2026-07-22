# frozen_string_literal: true

module Ibex
  # Parser table construction and row-displacement compression.
  module Tables
    TableSet = Struct.new(:actions, :gotos, :default_actions, keyword_init: true)

    # Sparse table represented by per-row offsets and ownership checks.
    class Compact
      attr_reader :offsets #: Array[Integer]
      attr_reader :values #: Array[untyped]
      attr_reader :checks #: Array[Integer?]
      attr_reader :row_count #: Integer

      # @rbs (Array[Hash[Integer, untyped]] rows) -> Compact
      def self.build(rows)
        offsets = Array.new(rows.length, 0)
        values = [] #: Array[untyped]
        checks = [] #: Array[Integer?]
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

      # @rbs (Array[Integer] columns, Array[Integer?] checks) -> Integer
      def self.find_offset(columns, checks)
        offset = 0
        offset += 1 while columns.any? { |column| checks[offset + column] }
        offset
      end
      private_class_method :find_offset

      # @rbs (offsets: Array[Integer], values: Array[untyped], checks: Array[Integer?], row_count: Integer) -> void
      def initialize(offsets:, values:, checks:, row_count:)
        @offsets = offsets.freeze
        @values = values.freeze
        @checks = checks.freeze
        @row_count = row_count
        freeze
      end

      # @rbs (Integer row, Integer column) -> untyped
      def lookup(row, column)
        return nil unless row.between?(0, @row_count - 1)
        return nil if column.negative?

        index = @offsets.fetch(row) + column
        return nil unless index.between?(0, @checks.length - 1)

        @checks[index] == row ? @values[index] : nil
      end

      # @rbs (Integer row) -> Hash[Integer, untyped]
      def row(row)
        return {} unless row.between?(0, @row_count - 1)

        result = {} #: Hash[Integer, untyped]
        @checks.each_index do |index|
          next unless @checks[index] == row

          result[index - @offsets[row]] = @values[index]
        end
        result
      end
    end

    module_function

    # @rbs (IR::Automaton automaton, ?format: Symbol | String) -> TableSet
    def build(automaton, format: :compact)
      action_rows = automaton.states.map { |state| state.actions.transform_values { |action| runtime_action(action) } }
      goto_rows = automaton.states.map(&:gotos)
      defaults = automaton.states.map do |state|
        runtime_action(state.default_action) if state.default_action
      end
      return TableSet.new(actions: action_rows, gotos: goto_rows, default_actions: defaults) if format.to_sym == :plain
      raise ArgumentError, "unknown table format #{format.inspect}" unless format.to_sym == :compact

      TableSet.new(actions: Compact.build(action_rows), gotos: Compact.build(goto_rows), default_actions: defaults)
    end

    # @rbs (IR::parser_action action) -> IR::runtime_action
    def runtime_action(action)
      case action.fetch(:type).to_sym
      when :shift
        shift = action #: IR::shift_action
        [:shift, shift.fetch(:state)]
      when :reduce
        reduce = action #: IR::reduce_action
        [:reduce, reduce.fetch(:production)]
      when :accept then [:accept]
      when :error then [:error]
      else raise Ibex::Error, "unknown parser action #{action.inspect}"
      end
    end
    private_class_method :runtime_action
  end
end
