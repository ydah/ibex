# frozen_string_literal: true

require_relative "normalize/declarations"
require_relative "normalize/context"
require_relative "normalize/parser_configuration"
require_relative "normalize/grammar_builder"
require_relative "normalize/lexer"
require_relative "normalize/recovery_declarations"
require_relative "normalize/expression"
require_relative "normalize/parameter_validation"
require_relative "normalize/inline_validation"
require_relative "normalize/parameter_substitution"
require_relative "normalize/parameter_ebnf_lowering"
require_relative "normalize/parameter_lowering"
require_relative "normalize/parameters"
require_relative "normalize/named_references"
require_relative "normalize/nodes"
require_relative "normalize/expander"
require_relative "normalize/inline_expansion"
require_relative "normalize/diagnostics"
require_relative "frontend/resolution"

module Ibex
  # Converts a frontend AST into immutable Grammar IR.
  class Normalizer
    include NormalizeDeclarations
    include NormalizeParserConfiguration
    include NormalizeGrammarBuilder
    include NormalizeLexer
    include NormalizeRecoveryDeclarations
    include NormalizeParameterValidation
    include NormalizeInlineValidation
    include NormalizeParameterSubstitution
    include NormalizeParameterEbnfLowering
    include NormalizeParameterLowering
    include NormalizeParameters
    include NormalizeNamedReferences
    include NormalizeNodes
    include NormalizeExpander
    include NormalizeInlineExpansion
    include NormalizeDiagnostics

    RESERVED_NAMES = %w[result val _values].freeze #: Array[String]
    RUBY_KEYWORDS = %w[
      __ENCODING__ __FILE__ __LINE__ alias and begin break case class def defined do else elsif end ensure false for if
      in module next nil not or redo rescue retry return self super then true undef unless until when while yield
    ].freeze #: Array[String]
    DEFAULT_MAX_PARAMETER_SPECIALIZATIONS = 1_000
    DEFAULT_MAX_INLINE_EXPANSIONS = 10_000

    attr_reader :context #: Normalize::Context

    # @rbs @ast: Frontend::AST::Root
    # @rbs @resolution: Frontend::Resolution?
    # @rbs @current_include_chain: Array[IR::source_provenance]
    # @rbs @mode: IR::grammar_mode
    # @rbs @symbols: Array[IR::GrammarSymbol]
    # @rbs @symbols_by_name: Hash[String, IR::GrammarSymbol]
    # @rbs @productions: Array[IR::Production]
    # @rbs @warnings: Array[IR::grammar_warning]
    # @rbs @helper_sequence: Integer
    # @rbs @declared_tokens: Hash[String, IR::location]
    # @rbs @precedence: Hash[String, IR::precedence]
    # @rbs @precedence_locations: Hash[String, IR::location]
    # @rbs @display_names: Hash[String, String]
    # @rbs @display_name_locations: Hash[String, IR::location]
    # @rbs @semantic_types: Hash[String, String]
    # @rbs @semantic_type_locations: Hash[String, IR::location]
    # @rbs @options: IR::grammar_options
    # @rbs @expected_conflicts: Integer
    # @rbs @expected_rr_conflicts: Integer?
    # @rbs @conversions: Hash[String, String]
    # @rbs @parser_parameters: Array[IR::parser_parameter]
    # @rbs @value_printers: Hash[String, IR::value_printer]
    # @rbs @recovery_sync_tokens: Array[String]
    # @rbs @on_error_reduce_groups: Array[Array[String]]
    # @rbs @grammar_tests: Array[IR::grammar_test]
    # @rbs @lexer_declaration: Frontend::AST::Lexer?
    # @rbs @parser_configuration: Frontend::AST::ParserConfiguration?
    # @rbs @explicit_starts: Array[String]?
    # @rbs @start_names: Array[String]
    # @rbs @start_name: String
    # @rbs @start_location: Frontend::Location?
    # @rbs @parameter_templates: Hash[String, Array[Frontend::AST::Rule]]
    # @rbs @parameter_formals: Hash[String, Array[String]]
    # @rbs @parameter_specializations: Hash[[String, Array[String]], String]
    # @rbs @parameter_worklist: Array[NormalizeParameters::parameter_frame]
    # @rbs @parameter_worklist_active: bool
    # @rbs @max_parameter_specializations: Integer
    # @rbs @current_parameter_expansion: IR::parameter_expansion?
    # @rbs @rule_documentation: Hash[String, String]
    # @rbs @inline_rule_names: Set[String]
    # @rbs @inline_symbol_ids: Set[Integer]
    # @rbs @inline_rule_by_symbol: Hash[Integer, String]
    # @rbs @max_inline_expansions: Integer
    # @rbs @inline_expansion_count: Integer
    # @rbs @node_shapes: Hash[String, Array[String]]

    # @rbs (Frontend::AST::Root | Frontend::AST::Fragment | Frontend::Resolution input,
    #   ?mode: Symbol | String, ?max_parameter_specializations: Integer,
    #   ?max_inline_expansions: Integer) -> void
    def initialize(input, mode: :default, max_parameter_specializations: DEFAULT_MAX_PARAMETER_SPECIALIZATIONS,
                   max_inline_expansions: DEFAULT_MAX_INLINE_EXPANSIONS)
      validate_positive_limit!(:max_parameter_specializations, max_parameter_specializations)
      validate_positive_limit!(:max_inline_expansions, max_inline_expansions)
      normalized_mode = mode.to_sym
      raise ArgumentError, "mode must be :default or :extended" unless %i[default extended].include?(normalized_mode)

      @resolution = input if input.is_a?(Frontend::Resolution)
      ast = input.is_a?(Frontend::Resolution) ? input.root : input
      normalized_mode = :extended if ast.is_a?(Frontend::AST::Root) && ast.extended
      fail_at(ast.loc, "fragments must be resolved before normalization") if ast.is_a?(Frontend::AST::Fragment)
      unresolved = ast.declarations.find { |declaration| declaration.is_a?(Frontend::AST::Include) }
      fail_at(unresolved.loc, "includes must be resolved before normalization") if unresolved

      @ast = ast
      @mode = normalized_mode #: IR::grammar_mode
      @context = Normalize::Context.new
      @symbols = [] #: Array[IR::GrammarSymbol]
      @symbols_by_name = {} #: Hash[String, IR::GrammarSymbol]
      @productions = [] #: Array[IR::Production]
      @warnings = [] #: Array[IR::grammar_warning]
      @helper_sequence = 0
      @current_include_chain = [] #: Array[IR::source_provenance]
      @parameter_specializations = {} #: Hash[[String, Array[String]], String]
      @parameter_worklist = [] #: Array[NormalizeParameters::parameter_frame]
      @parameter_worklist_active = false
      @max_parameter_specializations = max_parameter_specializations
      @max_inline_expansions = max_inline_expansions
      @inline_expansion_count = 0
      @inline_symbol_ids = Set.new #: Set[Integer]
      @inline_rule_by_symbol = {} #: Hash[Integer, String]
    end

    # @rbs () -> IR::Grammar
    def normalize
      phase(:declarations) { read_declarations }
      phase(:parameter_templates) { gather_parameter_templates }
      phase(:inline_rules) { gather_inline_rules }
      phase(:symbols) do
        intern_reserved_symbols
        intern_declared_terminals
        intern_user_nonterminals
      end
      parser_contract = phase(:parser_contract) { normalized_parser_contract }
      phase(:productions) { normalize_user_productions }
      phase(:expansions) { expand_inline_rules }
      phase(:validation) do
        validate_value_printers
        validate_recovery_declarations
        validate_grammar
      end
      phase(:build) { build_grammar(parser_contract) }
    end

    private

    # @rbs (Symbol phase) { () -> untyped } -> untyped
    def phase(name)
      @context.begin_phase!(name)
      result = yield
      @context.complete_phase!
      result
    end

    # @rbs (Symbol name, Object value) -> void
    def validate_positive_limit!(name, value)
      return if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive Integer"
    end

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
      @ast.rules.reject { |rule| parameterized_rule?(rule) }.each do |rule|
        intern_user_nonterminal(rule)
      end
      @start_names = normalized_start_names
      fail_at(@ast.loc, "grammar has no start rule") if @start_names.empty?
      @start_name = @start_names.fetch(0)
      @start_names.each do |name|
        next if symbol(name)&.nonterminal?

        fail_at(@start_location || @ast.loc, "undefined start symbol #{name}")
      end
    end

    # @rbs () -> Array[String]
    def normalized_start_names
      explicit = @explicit_starts
      return explicit if explicit

      candidate = @ast.rules.find { |rule| start_rule_candidate?(rule) }&.lhs
      candidate ? [candidate] : []
    end

    # @rbs (Frontend::AST::Rule rule) -> bool
    def start_rule_candidate?(rule)
      !parameterized_rule?(rule) && !rule.inline
    end

    # @rbs (Frontend::AST::Rule rule) -> void
    def intern_user_nonterminal(rule)
      definition = intern(
        rule.lhs, :nonterminal, location: rule.loc.to_h, documentation: @rule_documentation[rule.lhs]
      )
      return unless rule.inline

      @inline_symbol_ids << definition.id
      @inline_rule_by_symbol[definition.id] = rule.lhs
    end

    # @rbs () -> Hash[String, String]
    def validated_rule_documentation
      documentation = {} #: Hash[String, String]
      @ast.rules.each do |rule|
        text = rule.documentation
        next unless text

        existing = documentation[rule.lhs]
        fail_at(rule.loc, "conflicting documentation for rule #{rule.lhs}") if existing && existing != text

        documentation[rule.lhs] ||= text
      end
      documentation
    end

    # @rbs (String name, Symbol kind, ?reserved: bool, ?location: IR::location?,
    #   ?documentation: String?, ?metadata_name: String?) -> IR::GrammarSymbol
    def intern(name, kind, reserved: false, location: nil, documentation: nil, metadata_name: nil)
      existing = symbol(name)
      if existing
        fail_hash(location, "symbol #{name} is both terminal and nonterminal") if existing.kind != kind
        return existing
      end

      precedence = @precedence[name]
      metadata_key = metadata_name || name
      definition = IR::GrammarSymbol.new(id: @symbols.length, name: name, kind: kind, reserved: reserved,
                                         precedence: precedence, location: location,
                                         display_name: @display_names[metadata_key],
                                         semantic_type: @semantic_types[metadata_key], documentation: documentation)
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

      fail_at(reference.loc, "parameterized rule #{reference.name} requires arguments") if
        parameter_template?(reference.name)
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

    # @rbs () -> IR::production_expansion?
    def resolved_expansion
      return unless @resolution || @current_parameter_expansion

      { parameter: @current_parameter_expansion, inline: nil, include_chain: @current_include_chain }
    end
  end
end
