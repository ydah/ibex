# frozen_string_literal: true

require_relative "normalize/declarations"
require_relative "normalize/expander"
require_relative "normalize/diagnostics"

module Ibex
  # Converts a frontend AST into immutable Grammar IR.
  class Normalizer
    include NormalizeDeclarations
    include NormalizeExpander
    include NormalizeDiagnostics

    RESERVED_NAMES = %w[result val _values].freeze #: Array[String]

    # @rbs @ast: Frontend::AST::Root
    # @rbs @mode: Symbol
    # @rbs @symbols: Array[IR::GrammarSymbol]
    # @rbs @symbols_by_name: Hash[String, IR::GrammarSymbol]
    # @rbs @productions: Array[IR::Production]
    # @rbs @warnings: Array[IR::grammar_warning]
    # @rbs @helper_sequence: Integer
    # @rbs @declared_tokens: Hash[String, IR::location]
    # @rbs @precedence: Hash[String, IR::precedence]
    # @rbs @precedence_locations: Hash[String, IR::location]
    # @rbs @options: IR::grammar_options
    # @rbs @expected_conflicts: Integer
    # @rbs @conversions: Hash[String, String]
    # @rbs @explicit_start: String?
    # @rbs @start_name: String
    # @rbs @start_location: Frontend::Location?

    # @rbs (Frontend::AST::Root ast, ?mode: Symbol | String) -> void
    def initialize(ast, mode: :racc)
      @ast = ast
      @mode = mode
      @symbols = [] #: Array[IR::GrammarSymbol]
      @symbols_by_name = {} #: Hash[String, IR::GrammarSymbol]
      @productions = [] #: Array[IR::Production]
      @warnings = [] #: Array[IR::grammar_warning]
      @helper_sequence = 0
    end

    # @rbs () -> IR::Grammar
    def normalize
      read_declarations
      intern_reserved_symbols
      intern_declared_terminals
      intern_user_nonterminals
      normalize_user_productions
      validate_grammar
      IR::Grammar.new(class_name: @ast.class_name, superclass: @ast.superclass, start: @start_name,
                      expect: @expected_conflicts, options: @options, symbols: @symbols,
                      productions: @productions, user_code: normalized_user_code,
                      conversions: @conversions, warnings: @warnings, user_code_chunks: normalized_user_code_chunks)
    end

    private

    # @rbs () -> void
    def intern_reserved_symbols
      intern("$eof", :terminal, reserved: true)
      intern("error", :terminal, reserved: true)
    end

    # @rbs () -> void
    def intern_declared_terminals
      @declared_tokens.each { |name, loc| intern(name, :terminal, location: loc) }
      @precedence.each_key { |name| intern(name, :terminal, location: @precedence_locations[name]) }
    end

    # @rbs () -> void
    def intern_user_nonterminals
      @ast.rules.each { |rule| intern(rule.lhs, :nonterminal, location: rule.loc.to_h) }
      @start_name = @explicit_start || @ast.rules.first&.lhs
      fail_at(@ast.loc, "grammar has no start rule") unless @start_name
      return if symbol(@start_name)&.nonterminal?

      fail_at(@start_location || @ast.loc, "undefined start symbol #{@start_name}")
    end

    # @rbs (String name, Symbol kind, ?reserved: bool, ?location: IR::location?) -> IR::GrammarSymbol
    def intern(name, kind, reserved: false, location: nil)
      existing = symbol(name)
      if existing
        fail_hash(location, "symbol #{name} is both terminal and nonterminal") if existing.kind != kind
        return existing
      end

      precedence = @precedence[name]
      definition = IR::GrammarSymbol.new(id: @symbols.length, name: name, kind: kind, reserved: reserved,
                                         precedence: precedence, location: location)
      @symbols << definition
      @symbols_by_name[name] = definition
      definition
    end

    # @rbs (String name) -> IR::GrammarSymbol?
    def symbol(name)
      @symbols_by_name[name]
    end

    # @rbs (String name) -> IR::GrammarSymbol
    def required_symbol(name)
      symbol(name) || raise(Ibex::Error, "missing normalized symbol #{name}")
    end

    # @rbs (Frontend::AST::SymbolReference reference) -> IR::GrammarSymbol
    def symbol_for_reference(reference)
      existing = symbol(reference.name)
      return existing if existing
      return undefined_nonterminal(reference) if nonterminal_name?(reference.name)

      warn_undeclared_terminal(reference)
      intern(reference.name, :terminal, location: reference.loc.to_h)
    end

    # @rbs (String name) -> bool
    def nonterminal_name?(name)
      name.match?(/\A[a-z_]/) && name != "error"
    end

    # @rbs (Frontend::AST::SymbolReference reference) -> bot
    def undefined_nonterminal(reference)
      fail_at(reference.loc, "undefined nonterminal #{reference.name}")
    end

    # @rbs (Frontend::AST::SymbolReference reference) -> void
    def warn_undeclared_terminal(reference)
      return if @declared_tokens.empty? || reference.name.start_with?("'", '"')

      @warnings << { type: :undeclared_terminal, symbol: reference.name, loc: reference.loc.to_h }
    end

    # @rbs () -> Hash[String, String]
    def normalized_user_code
      %w[header inner footer].to_h do |name|
        [name, @ast.user_code.fetch(name, Array.new(0)).map(&:code).join]
      end
    end

    # @rbs () -> IR::user_code_chunks
    def normalized_user_code_chunks
      chunks_by_name = %w[header inner footer].to_h do |name|
        chunks = @ast.user_code.fetch(name, Array.new(0)).map do |block|
          location = block.loc.to_h.merge(line: block.loc.line + 1, column: 1)
          IR::UserCodeChunk.new(code: block.code, location: location)
        end
        [name, chunks]
      end
      chunks_by_name.reject { |_name, chunks| chunks.empty? }
    end

    # @rbs (Frontend::Location location, String message) -> bot
    def fail_at(location, message)
      raise Ibex::Error, "#{location}: #{message}"
    end

    # @rbs (IR::location? location, String message) -> bot
    def fail_hash(location, message)
      rendered = location ? "#{location[:file]}:#{location[:line]}:#{location[:column]}" : "(grammar):1:1"
      raise Ibex::Error, "#{rendered}: #{message}"
    end
  end
end
