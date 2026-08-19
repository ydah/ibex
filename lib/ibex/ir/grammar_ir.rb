# frozen_string_literal: true

require_relative "parser_contract"

module Ibex
  module IR
    # Grammar IR has one active wire format.  A future incompatible format
    # change may advance this number, but the runtime never treats old
    # formats as an alternate compatibility surface.
    SCHEMA_VERSION = 1
    SUPPORTED_SCHEMA_VERSIONS = [SCHEMA_VERSION].freeze #: Array[Integer]

    # Public IR constructors own their containers; callers keep ownership of
    # the values they pass in while the IR remains deeply immutable.
    # @rbs (Object? value) -> Object?
    def deep_freeze(value)
      case value
      when String
        value.dup.freeze
      when Array
        value.map { |item| deep_freeze(item) }.freeze
      when Hash
        value.to_h { |key, item| [deep_freeze(key), deep_freeze(item)] }.freeze
      else
        value.freeze
      end
    end
    module_function :deep_freeze

    # An interned terminal or nonterminal.
    class GrammarSymbol
      attr_reader :id #: Integer
      attr_reader :name #: String
      attr_reader :kind #: Symbol
      attr_reader :reserved #: bool
      attr_reader :precedence #: precedence?
      attr_reader :location #: location?
      attr_reader :display_name #: String?
      attr_reader :semantic_type #: String?
      attr_reader :documentation #: String?

      # @rbs (id: Integer, name: String, kind: Symbol, ?reserved: bool, ?precedence: precedence?,
      #   ?location: location?, ?display_name: String?, ?semantic_type: String?, ?documentation: String?) -> void
      def initialize(id:, name:, kind:, reserved: false, precedence: nil, location: nil, display_name: nil,
                     semantic_type: nil, documentation: nil)
        @id = id
        @name = name.dup.freeze
        @kind = kind.to_sym
        @reserved = reserved
        @precedence = IR.deep_freeze(precedence)
        @location = IR.deep_freeze(location)
        @display_name = display_name&.dup&.freeze
        @semantic_type = semantic_type&.dup&.freeze
        @documentation = documentation&.dup&.freeze
        freeze
      end

      # @rbs () -> bool
      def terminal? = @kind == :terminal
      # @rbs () -> bool
      def nonterminal? = @kind == :nonterminal

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        value = { id: @id, name: @name, kind: @kind, reserved: @reserved,
                  prec: @precedence, loc: @location } #: Hash[Symbol, Object?]
        value[:display_name] = @display_name if @display_name
        value[:semantic_type] = @semantic_type if @semantic_type
        value[:doc] = @documentation
        value
      end
    end

    # Opaque Ruby semantic action metadata.
    class Action
      attr_reader :code #: String
      attr_reader :location #: location
      attr_reader :named_refs #: Array[named_ref]
      attr_reader :context_length #: Integer
      attr_reader :composition #: action_composition?

      # @rbs (code: String, location: location, ?named_refs: Array[named_ref], ?context_length: Integer,
      #   ?composition: action_composition?) -> void
      def initialize(code:, location:, named_refs: [], context_length: 0, composition: nil)
        @code = code.dup.freeze
        @location = IR.deep_freeze(location)
        @named_refs = IR.deep_freeze(named_refs)
        @context_length = context_length
        @composition = IR.deep_freeze(composition)
        freeze
      end

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        value = { code: @code, loc: @location, named_refs: @named_refs,
                  context_length: @context_length } #: Hash[Symbol, Object?]
        value[:composition] = @composition
        value
      end
    end

    # A normalized BNF production using symbol ids.
    class Production
      attr_reader :id #: Integer
      attr_reader :lhs #: Integer
      attr_reader :rhs #: Array[Integer]
      attr_reader :action #: Action?
      attr_reader :precedence_override #: Integer?
      attr_reader :origin #: Hash[Symbol, Object?]
      attr_reader :documentation #: String?
      attr_reader :expansion #: production_expansion?
      attr_reader :node #: node_annotation?

      # @rbs (id: Integer, lhs: Integer, rhs: Array[Integer], action: Action?, precedence_override: Integer?,
      #   origin: Hash[Symbol, Object?], ?documentation: String?, ?expansion: production_expansion?,
      #   ?node: node_annotation?) -> void
      def initialize(id:, lhs:, rhs:, action:, precedence_override:, origin:, documentation: nil, expansion: nil,
                     node: nil)
        @id = id
        @lhs = lhs
        @rhs = IR.deep_freeze(rhs)
        @action = action
        @precedence_override = precedence_override
        @origin = IR.deep_freeze(origin)
        @documentation = documentation&.dup&.freeze
        @expansion = IR.deep_freeze(expansion)
        @node = IR.deep_freeze(node)
        freeze
      end

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        value = { id: @id, lhs: @lhs, rhs: @rhs, action: @action&.to_h,
                  prec_override: @precedence_override, origin: @origin } #: Hash[Symbol, Object?]
        value[:doc] = @documentation
        value[:expansion] = @expansion
        value[:node] = @node if @node
        value
      end
    end

    # One opaque user-code block and the location of its first code line.
    class UserCodeChunk
      attr_reader :code #: String
      attr_reader :location #: location

      # @rbs (code: String, location: location) -> void
      def initialize(code:, location:)
        @code = code.dup.freeze
        @location = IR.deep_freeze(location)
        freeze
      end

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        { code: @code, loc: @location }
      end
    end

    # Immutable normalized grammar exchanged between pipeline stages.
    class Grammar
      attr_reader :class_name #: String
      attr_reader :superclass #: String?
      attr_reader :start #: String
      attr_reader :starts #: Array[String]
      attr_reader :mode #: grammar_mode
      attr_reader :expect #: Integer
      attr_reader :expect_rr #: Integer?
      attr_reader :parser_parameters #: Array[parser_parameter]
      attr_reader :value_printers #: Array[value_printer]
      attr_reader :grammar_tests #: Array[grammar_test]
      attr_reader :lexer #: Lexer?
      attr_reader :recovery #: recovery_policy
      attr_reader :options #: grammar_options
      attr_reader :symbols #: Array[GrammarSymbol]
      attr_reader :productions #: Array[Production]
      attr_reader :user_code_chunks #: user_code_chunks
      attr_reader :conversions #: Hash[String, String]
      attr_reader :warnings #: Array[grammar_warning]
      attr_reader :schema_version #: Integer
      attr_reader :source_provenance #: source_provenance?
      attr_reader :parser_contract #: ParserContract

      # @rbs (class_name: String, superclass: String?, start: String, expect: Integer, ?expect_rr: Integer?,
      #   options: grammar_options,
      #   symbols: Array[GrammarSymbol], productions: Array[Production], user_code: Hash[String, String],
      #   conversions: Hash[String, String], warnings: Array[grammar_warning], ?user_code_chunks: user_code_chunks?,
      #   ?parser_parameters: Array[parser_parameter],
      #   ?value_printers: Array[value_printer], ?grammar_tests: Array[grammar_test],
      #   ?recovery: recovery_policy?, ?lexer: Lexer?,
      #   ?mode: grammar_mode, ?starts: Array[String]?, ?parser_contract: ParserContract,
      #   ?source_provenance: source_provenance?) -> void
      # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
      # Immutable current IR is constructed from explicit public fields.
      def initialize(class_name:, superclass:, start:, expect:, options:, symbols:, productions:, user_code:,
                     conversions:, warnings:, user_code_chunks: nil,
                     source_provenance: nil, expect_rr: nil, parser_parameters: [], value_printers: [],
                     grammar_tests: [], recovery: nil, lexer: nil, mode: :default, starts: nil,
                     parser_contract: ParserContract.new)
        initialize_current(
          class_name: class_name, superclass: superclass, start: start, expect: expect, options: options,
          symbols: symbols, productions: productions, user_code: user_code, conversions: conversions,
          warnings: warnings, user_code_chunks: user_code_chunks,
          source_provenance: source_provenance, expect_rr: expect_rr,
          parser_parameters: parser_parameters, value_printers: value_printers, grammar_tests: grammar_tests,
          recovery: recovery, lexer: lexer, mode: mode, starts: starts, parser_contract: parser_contract
        )
      end

      # @rbs (class_name: String, superclass: String?, start: String, expect: Integer, options: grammar_options,
      #   symbols: Array[GrammarSymbol], productions: Array[Production], user_code: Hash[String, String],
      #   conversions: Hash[String, String], warnings: Array[grammar_warning], user_code_chunks: user_code_chunks?,
      #   source_provenance: source_provenance?, expect_rr: Integer?, parser_parameters: Array[parser_parameter],
      #   value_printers: Array[value_printer], grammar_tests: Array[grammar_test], recovery: recovery_policy?,
      #   lexer: Lexer?, mode: grammar_mode, starts: Array[String]?, parser_contract: ParserContract) -> void
      # rubocop:disable Metrics/MethodLength -- explicit immutable field assignment is the IR constructor contract.
      def initialize_current(class_name:, superclass:, start:, expect:, options:, symbols:, productions:, user_code:,
                             conversions:, warnings:, user_code_chunks:, source_provenance:, expect_rr:,
                             parser_parameters:, value_printers:, grammar_tests:, recovery:, lexer:, mode:, starts:,
                             parser_contract:)
        validate_mode(mode)
        normalized_starts = validate_starts(start, starts, mode)
        validate_current_metadata(parser_contract)

        @class_name = class_name.dup.freeze
        @superclass = superclass&.dup&.freeze
        @start = start.dup.freeze
        @starts = normalized_starts.map { |value| value.dup.freeze }.freeze
        @mode = mode
        @expect = expect
        @expect_rr = expect_rr
        @parser_parameters = IR.deep_freeze(parser_parameters)
        @value_printers = IR.deep_freeze(value_printers)
        @grammar_tests = IR.deep_freeze(grammar_tests)
        @lexer = lexer
        @recovery = IR.deep_freeze(recovery || { sync_tokens: [], on_error_reduce: [] })
        @options = IR.deep_freeze(options)
        @symbols = symbols.dup.freeze
        @productions = productions.dup.freeze
        @user_code_chunks = IR.deep_freeze(user_code_chunks || {})
        validate_user_code_chunks(user_code)
        @user_code_names = user_code.keys.map { |name| name.dup.freeze }.freeze
        @legacy_user_code = IR.deep_freeze(
          user_code.reject { |name, _code| @user_code_chunks.key?(name) }
        )
        @conversions = IR.deep_freeze(conversions)
        @warnings = IR.deep_freeze(warnings)
        @schema_version = SCHEMA_VERSION
        @source_provenance = IR.deep_freeze(source_provenance)
        @parser_contract = IR.deep_freeze(parser_contract)
        @symbols_by_name = @symbols.to_h { |symbol| [symbol.name, symbol] }.freeze
        @symbols_by_id = @symbols.to_h { |symbol| [symbol.id, symbol] }.freeze
        freeze
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize, Metrics/ParameterLists
      private :initialize_current

      # @rbs (String name) -> GrammarSymbol?
      def symbol(name) = @symbols_by_name[name]

      # @rbs () -> Hash[String, String]
      def user_code
        @user_code_names.to_h do |name|
          code = if @user_code_chunks.key?(name)
                   @user_code_chunks.fetch(name).map(&:code).join
                 else
                   @legacy_user_code.fetch(name)
                 end
          [name, code]
        end
          .freeze
      end

      # @rbs (Integer? id) -> GrammarSymbol?
      def symbol_by_id(id) = @symbols_by_id[id]
      # @rbs () -> Array[GrammarSymbol]
      def terminals = @symbols.select(&:terminal?)
      # @rbs () -> Array[GrammarSymbol]
      def nonterminals = @symbols.select(&:nonterminal?)

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        value = { ibex_ir: "grammar", schema_version: @schema_version, class_name: @class_name, superclass: @superclass,
                  start: @start, expect: @expect, options: @options,
                  symbols: @symbols.map(&:to_h),
                  productions: @productions.map(&:to_h),
                  user_code: user_code, conversions: @conversions,
                  warnings: @warnings } #: Hash[Symbol, Object?]
        append_optional_metadata(value)
        value
      end

      private

      # @rbs (grammar_mode mode) -> void
      def validate_mode(mode)
        raise ArgumentError, "mode must be :default or :extended" unless %i[default extended].include?(mode)
      end

      # @rbs (String start, Array[String]? starts, grammar_mode mode) -> Array[String]
      def validate_starts(start, starts, mode)
        values = starts || [start]
        raise ArgumentError, "starts must contain the primary start symbol" if values.empty?
        raise ArgumentError, "start must be the first entry in starts" unless values.first == start
        raise ArgumentError, "starts must be unique" unless values.uniq.length == values.length
        raise ArgumentError, "multiple start symbols require extended mode" if values.length > 1 && mode != :extended

        values
      end

      # @rbs (Hash[Symbol, Object?] value) -> void
      def append_optional_metadata(value)
        append_parser_metadata(value)
        append_recovery_metadata(value)
        value[:user_code_chunks] = @user_code_chunks.transform_values { |chunks| chunks.map(&:to_h) } \
          unless @user_code_chunks.empty?
        value[:source_provenance] = @source_provenance
        value[:parser_contract] = @parser_contract.to_h
      end

      # @rbs (Hash[Symbol, Object?] value) -> void
      def append_parser_metadata(value)
        value[:expect_rr] = @expect_rr unless @expect_rr.nil?
        value[:mode] = @mode if @mode == :extended
        value[:starts] = @starts if @starts.length > 1
        value[:params] = @parser_parameters unless @parser_parameters.empty?
        value[:printers] = @value_printers unless @value_printers.empty?
        value[:tests] = @grammar_tests unless @grammar_tests.empty?
        value[:lexer] = @lexer.to_h if @lexer
      end

      # @rbs (Hash[Symbol, Object?] value) -> void
      def append_recovery_metadata(value)
        return if @recovery[:sync_tokens].empty? && @recovery[:on_error_reduce].empty?

        value[:recovery] = @recovery
      end

      # @rbs (Hash[String, String] user_code) -> void
      def validate_user_code_chunks(user_code)
        @user_code_chunks.each do |name, chunks|
          next if chunks.map(&:code).join == user_code.fetch(name, "")

          raise Ibex::Error, "(ir):1:1: user-code chunks do not match the concatenated #{name} section"
        end
      end

      # @rbs (ParserContract parser_contract) -> void
      def validate_current_metadata(parser_contract)
        return if parser_contract.is_a?(ParserContract)

        raise ArgumentError, "parser_contract must be a ParserContract"
      end
    end
  end
end
