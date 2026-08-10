# frozen_string_literal: true

module Ibex
  # Static grammar diagnostics used by Normalizer.
  module NormalizeDiagnostics
    private

    # @rbs () -> void
    def validate_grammar
      # @type self: Normalizer
      validate_symbol_metadata
      warn_duplicate_productions
      warn_unreachable_nonterminals
      warn_unreachable_terminals
      warn_unused_terminals
      warn_unused_precedence
      warn_empty_language
    end

    # @rbs () -> void
    def validate_symbol_metadata
      # @type self: Normalizer
      display_locations = @display_name_locations #: Hash[String, IR::location]
      semantic_locations = @semantic_type_locations #: Hash[String, IR::location]
      inline_rule_names = @inline_rule_names #: Set[String]
      { display: display_locations, type: semantic_locations }.each do |label, locations|
        locations.each do |name, location|
          fail_hash(location, "#{label} declaration references undefined symbol #{name}") unless
            symbol(name) || parameter_template?(name) || (label == :type && inline_rule_names.include?(name))
        end
      end
    end

    # @rbs () -> void
    def warn_duplicate_productions
      # @type self: Normalizer
      productions = @productions #: Array[IR::Production]
      warnings = @warnings #: Array[IR::grammar_warning]
      seen = {} #: Hash[[Integer, Array[Integer]], Integer]
      productions.each do |production|
        signature = [production.lhs, production.rhs] #: [Integer, Array[Integer]]
        if seen.key?(signature)
          location = production.origin[:loc] #: IR::location?
          warnings << { type: :duplicate_production, production: production.id, original: seen[signature],
                        loc: location }
        else
          seen[signature] = production.id
        end
      end
    end

    # @rbs () -> void
    def warn_unreachable_nonterminals
      # @type self: Normalizer
      symbols = @symbols #: Array[IR::GrammarSymbol]
      warnings = @warnings #: Array[IR::grammar_warning]
      reachable = reachable_symbol_ids
      symbols.select(&:nonterminal?).each do |grammar_symbol|
        next if reachable.key?(grammar_symbol.id) || grammar_symbol.name.start_with?("$")

        warnings << { type: :unreachable_nonterminal, symbol: grammar_symbol.name, loc: grammar_symbol.location }
      end
    end

    # @rbs () -> Hash[Integer, true]
    def reachable_symbol_ids
      # @type self: Normalizer
      start_names = @start_names #: Array[String]
      productions = @productions #: Array[IR::Production]
      starts = start_names.map { |name| required_symbol(name).id }
      reachable = starts.to_h { |id| [id, true] } #: Hash[Integer, true]
      loop do
        before = reachable.length
        productions.select { |production| reachable.key?(production.lhs) }.each do |production|
          production.rhs.each { |id| reachable[id] = true }
        end
        return reachable if reachable.length == before
      end
    end

    # @rbs () -> void
    def warn_unused_terminals
      # @type self: Normalizer
      productions = @productions #: Array[IR::Production]
      symbols = @symbols #: Array[IR::GrammarSymbol]
      precedence = @precedence #: Hash[String, IR::precedence]
      warnings = @warnings #: Array[IR::grammar_warning]
      used = productions.flat_map(&:rhs).to_h { |id| [id, true] } #: Hash[Integer, true]
      symbols.select(&:terminal?).each do |grammar_symbol|
        next if grammar_symbol.reserved || used.key?(grammar_symbol.id) || precedence.key?(grammar_symbol.name)

        warnings << { type: :unused_terminal, symbol: grammar_symbol.name, loc: grammar_symbol.location }
      end
    end

    # @rbs () -> void
    def warn_unreachable_terminals
      # @type self: Normalizer
      productions = @productions #: Array[IR::Production]
      declared_tokens = @declared_tokens #: Hash[String, IR::location]
      warnings = @warnings #: Array[IR::grammar_warning]
      reachable = reachable_symbol_ids
      used = productions.flat_map(&:rhs).to_h { |id| [id, true] } #: Hash[Integer, true]
      declared_tokens.each_key do |name|
        grammar_symbol = required_symbol(name)
        next unless used.key?(grammar_symbol.id)
        next if reachable.key?(grammar_symbol.id)

        warnings << { type: :unreachable_terminal, symbol: name, loc: declared_tokens[name] }
      end
    end

    # @rbs () -> void
    def warn_unused_precedence
      # @type self: Normalizer
      productions = @productions #: Array[IR::Production]
      precedence = @precedence #: Hash[String, IR::precedence]
      precedence_locations = @precedence_locations #: Hash[String, IR::location]
      warnings = @warnings #: Array[IR::grammar_warning]
      referenced = {} # @type var referenced: Hash[Integer, true]
      productions.each do |production|
        symbol_ids = referenced
        production.rhs.each { |id| symbol_ids[id] = true }
        symbol_ids[production.precedence_override] = true if production.precedence_override
      end
      precedence.each_key do |name|
        grammar_symbol = required_symbol(name)
        next if referenced.key?(grammar_symbol.id)

        warnings << { type: :unused_precedence, symbol: name, loc: precedence_locations[name] }
      end
    end

    # @rbs () -> void
    def warn_empty_language
      # @type self: Normalizer
      productions = @productions #: Array[IR::Production]
      start_names = @start_names #: Array[String]
      warnings = @warnings #: Array[IR::grammar_warning]
      productive = productive_terminal_ids
      loop do
        before = productive.length
        productions.each do |production|
          productive[production.lhs] = true if production.rhs.all? { |id| productive.key?(id) }
        end
        break if productive.length == before
      end
      start_names.each do |name|
        next if productive.key?(required_symbol(name).id)

        start_symbol = required_symbol(name)
        warnings << { type: :empty_language, symbol: name, loc: start_symbol.location }
      end
    end

    # @rbs () -> Hash[Integer, true]
    def productive_terminal_ids
      # @type self: Normalizer
      symbols = @symbols #: Array[IR::GrammarSymbol]
      symbols.select { |grammar_symbol| productive_terminal?(grammar_symbol) }.to_h { |symbol| [symbol.id, true] }
    end

    # @rbs (IR::GrammarSymbol grammar_symbol) -> bool
    def productive_terminal?(grammar_symbol)
      # @type self: Normalizer
      grammar_symbol.terminal? && !grammar_symbol.reserved
    end
  end
end
