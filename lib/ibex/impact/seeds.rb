# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Impact
    # Converts command-line symbols and Diff rule ids into analysis seeds.
    class Seeds
      # @rbs @grammar: IR::Grammar
      # @rbs @sets: Analysis::Sets
      # @rbs @records: Array[Hash[Symbol, Object?]]
      # @rbs @ids: Array[Integer]
      attr_reader :ids #: Array[Integer]
      attr_reader :records #: Array[Hash[Symbol, Object?]]

      # @rbs (IR::Grammar grammar, Array[String] names, ?origin: String) -> void
      def initialize(grammar, names, origin: "symbol")
        @grammar = grammar
        @sets = Analysis::Sets.new(grammar)
        @records = names.flat_map { |name| resolve(name, origin) }.sort_by { |record| seed_symbol(record) }
        @ids = @records.map { |record| seed_id(record) }.uniq.freeze
        @records = @records.freeze
        freeze
      end

      # @rbs (IR::Grammar grammar, Hash[Symbol, Object?] diff, ?origin: String) -> Seeds
      def self.from_diff(grammar, diff, origin: "diff")
        rules = diff.fetch(:rules) #: Hash[Symbol, Object?]
        names = %i[added removed changed].flat_map do |section|
          records = rules.fetch(section) #: Array[Hash[Symbol, Object?]]
          records.map { |record| record.fetch(:id).to_s }
        end.uniq.sort
        new(grammar, names, origin: origin)
      end

      private

      # @rbs (Hash[Symbol, Object?] record) -> String
      def seed_symbol(record)
        record.fetch(:symbol) #: String
      end

      # @rbs (Hash[Symbol, Object?] record) -> Integer
      def seed_id(record)
        record.fetch(:id) #: Integer
      end

      # @rbs (String name, String origin) -> Array[Hash[Symbol, Object?]]
      def resolve(name, origin)
        definition = @grammar.symbol(name)
        raise Ibex::Error, "(impact):1:1: unknown symbol #{name}" unless definition
        raise Ibex::Error, "(impact):1:1: impact seed #{name} is not a nonterminal" unless definition.nonterminal?

        [{ symbol: definition.name, id: definition.id, origin: origin,
           nullable_boundary: nullable_boundary?(definition.id) }]
      end

      # @rbs (Integer) -> bool
      def nullable_boundary?(id)
        return true if @sets.nullable?(id)

        @grammar.productions.any? do |production|
          production.rhs.include?(id) && production.rhs.any? do |symbol_id|
            @grammar.symbol_by_id(symbol_id)&.nonterminal? && @sets.nullable?(symbol_id)
          end
        end
      end
    end
  end
end
