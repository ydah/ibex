# frozen_string_literal: true

require "set"

module Ibex
  # Static grammar diagnostics used by Normalizer.
  module NormalizeDiagnostics
    private

    def validate_grammar
      warn_duplicate_productions
      warn_unreachable_nonterminals
      warn_unused_terminals
    end

    def warn_duplicate_productions
      seen = {}
      @productions.each do |production|
        signature = [production.lhs, production.rhs]
        if seen.key?(signature)
          @warnings << { type: :duplicate_production, production: production.id, original: seen[signature],
                         loc: production.origin[:loc] }
        else
          seen[signature] = production.id
        end
      end
    end

    def warn_unreachable_nonterminals
      reachable = reachable_symbol_ids
      @symbols.select(&:nonterminal?).each do |grammar_symbol|
        next if reachable.include?(grammar_symbol.id) || grammar_symbol.name.start_with?("$")

        @warnings << { type: :unreachable_nonterminal, symbol: grammar_symbol.name, loc: grammar_symbol.location }
      end
    end

    def reachable_symbol_ids
      start = symbol(@start_name).id
      reachable = Set[start]
      loop do
        before = reachable.length
        @productions.select { |production| reachable.include?(production.lhs) }.each do |production|
          production.rhs.each { |id| reachable << id }
        end
        return reachable if reachable.length == before
      end
    end

    def warn_unused_terminals
      used = @productions.flat_map(&:rhs).to_set
      @symbols.select(&:terminal?).each do |grammar_symbol|
        next if grammar_symbol.reserved || used.include?(grammar_symbol.id) || @precedence.key?(grammar_symbol.name)

        @warnings << { type: :unused_terminal, symbol: grammar_symbol.name, loc: grammar_symbol.location }
      end
    end
  end
end
