# frozen_string_literal: true

module Ibex
  module Analysis
    # Computes nullable, FIRST, and FOLLOW sets over Grammar IR using integer bitsets.
    class Sets
      attr_reader :nullable_bits, :first_bits, :follow_bits

      def initialize(grammar)
        @grammar = grammar
        @nullable_bits = 0
        @first_bits = Array.new(grammar.symbols.length, 0)
        @follow_bits = Array.new(grammar.symbols.length, 0)
        grammar.terminals.each { |terminal| @first_bits[terminal.id] = bit(terminal.id) }
        compute_nullable
        compute_first
        compute_follow
      end

      def nullable?(symbol)
        id = symbol_id(symbol)
        @nullable_bits.anybits?(bit(id))
      end

      def first(symbol)
        terminal_names(@first_bits.fetch(symbol_id(symbol)))
      end

      def follow(symbol)
        definition = definition_for(symbol)
        raise Ibex::Error, "(analysis):1:1: FOLLOW is only defined for nonterminals" unless definition.nonterminal?

        terminal_names(@follow_bits.fetch(definition.id))
      end

      def first_of_sequence(symbol_ids)
        bits = 0
        symbol_ids.each do |id|
          bits |= @first_bits.fetch(id)
          return bits unless nullable_id?(id)
        end
        bits
      end

      def sequence_nullable?(symbol_ids)
        symbol_ids.all? { |id| nullable_id?(id) }
      end

      private

      def compute_nullable
        loop do
          before = @nullable_bits
          @grammar.productions.each do |production|
            @nullable_bits |= bit(production.lhs) if production.rhs.all? { |id| nullable_id?(id) }
          end
          return if before == @nullable_bits
        end
      end

      def compute_first
        loop do
          changed = false
          @grammar.productions.each do |production|
            previous = @first_bits[production.lhs]
            @first_bits[production.lhs] |= first_of_sequence(production.rhs)
            changed ||= previous != @first_bits[production.lhs]
          end
          return unless changed
        end
      end

      def compute_follow
        start_id = @grammar.symbol(@grammar.start).id
        @follow_bits[start_id] |= bit(0)
        loop do
          changed = false
          @grammar.productions.each { |production| changed ||= propagate_follow(production) }
          return unless changed
        end
      end

      def propagate_follow(production)
        changed = false
        trailer = @follow_bits[production.lhs]
        production.rhs.reverse_each do |id|
          definition = @grammar.symbol_by_id(id)
          if definition.nonterminal?
            previous = @follow_bits[id]
            @follow_bits[id] |= trailer
            changed ||= previous != @follow_bits[id]
            trailer = @first_bits[id] | (nullable_id?(id) ? trailer : 0)
          else
            trailer = @first_bits[id]
          end
        end
        changed
      end

      def nullable_id?(id)
        @nullable_bits.anybits?(bit(id))
      end

      def terminal_names(bits)
        @grammar.terminals.filter_map { |terminal| terminal.name if bits.anybits?(bit(terminal.id)) }
      end

      def symbol_id(symbol)
        definition_for(symbol).id
      end

      def definition_for(symbol)
        definition = symbol.is_a?(Integer) ? @grammar.symbol_by_id(symbol) : @grammar.symbol(symbol.to_s)
        return definition if definition

        raise Ibex::Error, "(analysis):1:1: unknown symbol #{symbol}"
      end

      def bit(id)
        1 << id
      end
    end
  end
end
