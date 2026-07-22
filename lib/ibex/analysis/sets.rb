# frozen_string_literal: true

module Ibex
  module Analysis
    # Computes nullable, FIRST, and FOLLOW sets over Grammar IR using integer bitsets.
    class Sets
      attr_reader :nullable_bits #: Integer
      attr_reader :first_bits #: Array[Integer]
      attr_reader :follow_bits #: Array[Integer]

      # @rbs @grammar: IR::Grammar

      # @rbs (IR::Grammar grammar) -> void
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

      # @rbs (Integer | String | Symbol | IR::GrammarSymbol symbol) -> bool
      def nullable?(symbol)
        id = symbol_id(symbol)
        @nullable_bits.anybits?(bit(id))
      end

      # @rbs (Integer | String | Symbol | IR::GrammarSymbol symbol) -> Array[String]
      def first(symbol)
        terminal_names(@first_bits.fetch(symbol_id(symbol)))
      end

      # @rbs (Integer | String | Symbol | IR::GrammarSymbol symbol) -> Array[String]
      def follow(symbol)
        definition = definition_for(symbol)
        raise Ibex::Error, "(analysis):1:1: FOLLOW is only defined for nonterminals" unless definition.nonterminal?

        terminal_names(@follow_bits.fetch(definition.id))
      end

      # @rbs (Array[Integer] symbol_ids) -> Integer
      def first_of_sequence(symbol_ids)
        bits = 0
        symbol_ids.each do |id|
          bits |= @first_bits.fetch(id)
          return bits unless nullable_id?(id)
        end
        bits
      end

      # @rbs (Array[Integer] symbol_ids) -> bool
      def sequence_nullable?(symbol_ids)
        symbol_ids.all? { |id| nullable_id?(id) }
      end

      private

      # @rbs () -> void
      def compute_nullable
        dependencies, remaining, queue = nullable_worklist

        until queue.empty?
          id = queue.shift
          next if nullable_id?(id)

          @nullable_bits |= bit(id)
          dependencies[id].each do |production|
            remaining[production.id] -= 1
            queue << production.lhs if remaining[production.id].zero?
          end
        end
      end

      # @rbs () -> [Array[Array[IR::Production]], Array[Integer], Array[Integer]]
      def nullable_worklist
        dependencies = Array.new(@grammar.symbols.length) { [] }
        remaining = Array.new(@grammar.productions.length, 0)
        queue = [] #: Array[Integer]
        @grammar.productions.each do |production|
          next if production.rhs.any? { |id| required_symbol_by_id(id).terminal? }

          remaining[production.id] = production.rhs.length
          production.rhs.each { |id| dependencies[id] << production }
          queue << production.lhs if production.rhs.empty?
        end
        [dependencies, remaining, queue]
      end

      # @rbs () -> void
      def compute_first
        dependencies = Array.new(@grammar.symbols.length) { [] }
        @grammar.productions.each do |production|
          production.rhs.each do |id|
            dependencies[id] << production.lhs
            break unless nullable_id?(id)
          end
        end

        propagate_bits(@first_bits, dependencies, @grammar.terminals.map(&:id))
      end

      # @rbs () -> void
      def compute_follow
        start_definition = @grammar.symbol(@grammar.start)
        raise Ibex::Error, "(analysis):1:1: unknown start symbol #{@grammar.start}" unless start_definition

        start_id = start_definition.id
        @follow_bits[start_id] |= bit(0)
        dependencies = Array.new(@grammar.symbols.length) { [] }
        @grammar.productions.each { |production| initialize_follow(production, dependencies) }
        seeds = @grammar.nonterminals.filter_map { |symbol| symbol.id unless @follow_bits[symbol.id].zero? }
        propagate_bits(@follow_bits, dependencies, seeds)
      end

      # @rbs (IR::Production production, Array[Array[Integer]] dependencies) -> void
      def initialize_follow(production, dependencies)
        trailer = 0
        suffix_nullable = true
        production.rhs.reverse_each do |id|
          definition = required_symbol_by_id(id)
          if definition.nonterminal?
            @follow_bits[id] |= trailer
            dependencies[production.lhs] << id if suffix_nullable
            trailer = @first_bits[id] | (nullable_id?(id) ? trailer : 0)
            suffix_nullable &&= nullable_id?(id)
          else
            trailer = @first_bits[id]
            suffix_nullable = false
          end
        end
      end

      # @rbs (Array[Integer] sets, Array[Array[Integer]] dependencies, Array[Integer] seeds) -> void
      def propagate_bits(sets, dependencies, seeds)
        queue = seeds.dup
        queued = Array.new(@grammar.symbols.length, false)
        queue.each { |id| queued[id] = true }

        until queue.empty?
          source = queue.shift
          queued[source] = false
          dependencies[source].each do |target|
            combined = sets[target] | sets[source]
            next if combined == sets[target]

            sets[target] = combined
            next if queued[target]

            queued[target] = true
            queue << target
          end
        end
      end

      # @rbs (Integer id) -> bool
      def nullable_id?(id)
        @nullable_bits.anybits?(bit(id))
      end

      # @rbs (Integer bits) -> Array[String]
      def terminal_names(bits)
        @grammar.terminals.filter_map { |terminal| terminal.name if bits.anybits?(bit(terminal.id)) }
      end

      # @rbs (Integer | String | Symbol | IR::GrammarSymbol symbol) -> Integer
      def symbol_id(symbol)
        definition_for(symbol).id
      end

      # @rbs (Integer | String | Symbol | IR::GrammarSymbol symbol) -> IR::GrammarSymbol
      def definition_for(symbol)
        return symbol if symbol.is_a?(IR::GrammarSymbol)

        definition = symbol.is_a?(Integer) ? @grammar.symbol_by_id(symbol) : @grammar.symbol(symbol.to_s)
        return definition if definition

        raise Ibex::Error, "(analysis):1:1: unknown symbol #{symbol}"
      end

      # @rbs (Integer id) -> IR::GrammarSymbol
      def required_symbol_by_id(id)
        @grammar.symbol_by_id(id) || raise(Ibex::Error, "(analysis):1:1: unknown symbol id #{id}")
      end

      # @rbs (Integer id) -> Integer
      def bit(id)
        1 << id
      end
    end
  end
end
