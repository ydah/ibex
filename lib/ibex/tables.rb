# frozen_string_literal: true

module Ibex
  # Parser table construction and row-displacement compression.
  module Tables
    # @rbs!
    #   private def runtime_action: (IR::parser_action action) -> IR::runtime_action
    #   private def self.runtime_action: (IR::parser_action action) -> IR::runtime_action

    TableSet = Struct.new(:actions, :gotos, :default_actions, keyword_init: true)

    # Sparse table represented by per-row offsets and ownership checks.
    class Compact
      attr_reader :offsets #: Array[Integer]
      attr_reader :values #: Array[untyped]
      attr_reader :checks #: Array[Integer?]
      attr_reader :row_count #: Integer

      class << self
        # @rbs (Array[Hash[Integer, untyped]] rows) -> Compact
        def build(rows)
          offsets = Array.new(rows.length, 0)
          values = [] #: Array[untyped]
          checks = [] #: Array[Integer?]
          next_offsets = {} #: Hash[Array[Integer], Integer]
          rows.each_index.sort_by { |row| [-rows[row].length, row] }.each do |row|
            offset = find_offset(rows[row].keys, checks, next_offsets)
            offsets[row] = offset
            rows[row].each do |column, value|
              index = offset + column
              values[index] = value
              checks[index] = row
            end
          end
          new(offsets: offsets, values: values, checks: checks, row_count: rows.length)
        end

        private

        # @rbs (Array[Integer] columns, Array[Integer?] checks, Hash[Array[Integer], Integer] next_offsets) -> Integer
        def find_offset(columns, checks, next_offsets)
          return 0 if columns.empty?

          signature = columns.sort
          offset = next_offsets.fetch(signature, 0)
          offset += 1 while columns.any? { |column| checks[offset + column] }
          next_offsets[signature] = offset + 1
          offset
        end
      end

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

    # @rbs (IR::Automaton automaton, ?format: Symbol | String) -> TableSet
    def build(automaton, format: :compact)
      action_rows = automaton.states.map do |state|
        state.actions.transform_values do |action|
          runtime_action(action)
        end
      end
      goto_rows = automaton.states.map(&:gotos)
      defaults = automaton.states.map do |state|
        runtime_action(state.default_action) if state.default_action
      end
      if format.to_sym == :plain
        return TableSet.new(actions: action_rows, gotos: goto_rows,
                            default_actions: defaults)
      end
      raise ArgumentError, "unknown table format #{format.inspect}" unless format.to_sym == :compact

      TableSet.new(actions: Compact.build(action_rows), gotos: Compact.build(goto_rows), default_actions: defaults)
    end
    module_function :build

    # @rbs skip
    private

    # @rbs skip
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
    module_function :runtime_action

    class << self
      private :runtime_action
    end
  end
end
