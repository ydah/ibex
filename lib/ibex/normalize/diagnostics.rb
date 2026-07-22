# frozen_string_literal: true

require "set"

module Ibex
  # Static grammar diagnostics used by Normalizer.
  module NormalizeDiagnostics
    private

    # @rbs () -> void
    def validate_grammar
      # @type self: Normalizer
      warn_duplicate_productions
      warn_unreachable_nonterminals
      warn_unused_terminals
      warn_empty_language
    end

    # @rbs () -> void
    def warn_duplicate_productions
      # @type self: Normalizer
      seen = {} #: Hash[[Integer, Array[Integer]], Integer]
      @productions.each do |production|
        signature = [production.lhs, production.rhs] #: [Integer, Array[Integer]]
        if seen.key?(signature)
          @warnings << { type: :duplicate_production, production: production.id, original: seen[signature],
                         loc: production.origin[:loc] }
        else
          seen[signature] = production.id
        end
      end
    end

    # @rbs () -> void
    def warn_unreachable_nonterminals
      # @type self: Normalizer
      reachable = reachable_symbol_ids
      @symbols.select(&:nonterminal?).each do |grammar_symbol|
        next if reachable.include?(grammar_symbol.id) || grammar_symbol.name.start_with?("$")

        @warnings << { type: :unreachable_nonterminal, symbol: grammar_symbol.name, loc: grammar_symbol.location }
      end
    end

    # @rbs () -> Set[Integer]
    def reachable_symbol_ids
      # @type self: Normalizer
      start = required_symbol(@start_name).id
      reachable = Set[start]
      loop do
        before = reachable.length
        @productions.select { |production| reachable.include?(production.lhs) }.each do |production|
          production.rhs.each { |id| reachable << id }
        end
        return reachable if reachable.length == before
      end
    end

    # @rbs () -> void
    def warn_unused_terminals
      # @type self: Normalizer
      used = @productions.flat_map(&:rhs).to_set
      @symbols.select(&:terminal?).each do |grammar_symbol|
        next if grammar_symbol.reserved || used.include?(grammar_symbol.id) || @precedence.key?(grammar_symbol.name)

        @warnings << { type: :unused_terminal, symbol: grammar_symbol.name, loc: grammar_symbol.location }
      end
    end

    # @rbs () -> void
    def warn_empty_language
      # @type self: Normalizer
      productive = productive_terminal_ids
      loop do
        before = productive.length
        @productions.each do |production|
          productive << production.lhs if production.rhs.all? { |id| productive.include?(id) }
        end
        break if productive.length == before
      end
      return if productive.include?(required_symbol(@start_name).id)

      start_symbol = required_symbol(@start_name)
      @warnings << { type: :empty_language, symbol: @start_name, loc: start_symbol.location }
    end

    # @rbs () -> Set[Integer]
    def productive_terminal_ids
      # @type self: Normalizer
      @symbols.select { |grammar_symbol| productive_terminal?(grammar_symbol) }.to_set(&:id)
    end

    # @rbs (IR::GrammarSymbol grammar_symbol) -> bool
    def productive_terminal?(grammar_symbol)
      # @type self: Normalizer
      grammar_symbol.terminal? && !grammar_symbol.reserved
    end
  end
end
