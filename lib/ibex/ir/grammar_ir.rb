# frozen_string_literal: true

module Ibex
  module IR
    SCHEMA_VERSION = 1

    # @rbs (untyped value) -> untyped
    def deep_freeze(value)
      case value
      when Array then value.each { |item| deep_freeze(item) }
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      end
      value.freeze
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

      # @rbs (id: Integer, name: String, kind: Symbol, ?reserved: bool, ?precedence: precedence?,
      #   ?location: location?) -> void
      def initialize(id:, name:, kind:, reserved: false, precedence: nil, location: nil)
        @id = id
        @name = name.freeze
        @kind = kind.to_sym
        @reserved = reserved
        @precedence = IR.deep_freeze(precedence)
        @location = IR.deep_freeze(location)
        freeze
      end

      # @rbs () -> bool
      def terminal? = @kind == :terminal
      # @rbs () -> bool
      def nonterminal? = @kind == :nonterminal

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { id: @id, name: @name, kind: @kind, reserved: @reserved, prec: @precedence, loc: @location }
      end
    end

    # Opaque Ruby semantic action metadata.
    class Action
      attr_reader :code #: String
      attr_reader :location #: location
      attr_reader :named_refs #: Array[named_ref]
      attr_reader :context_length #: Integer

      # @rbs (code: String, location: location, ?named_refs: Array[named_ref], ?context_length: Integer) -> void
      def initialize(code:, location:, named_refs: [], context_length: 0)
        @code = code.freeze
        @location = IR.deep_freeze(location)
        @named_refs = IR.deep_freeze(named_refs)
        @context_length = context_length
        freeze
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { code: @code, loc: @location, named_refs: @named_refs, context_length: @context_length }
      end
    end

    # A normalized BNF production using symbol ids.
    class Production
      attr_reader :id #: Integer
      attr_reader :lhs #: Integer
      attr_reader :rhs #: Array[Integer]
      attr_reader :action #: Action?
      attr_reader :precedence_override #: Integer?
      attr_reader :origin #: Hash[Symbol, untyped]

      # @rbs (id: Integer, lhs: Integer, rhs: Array[Integer], action: Action?, precedence_override: Integer?,
      #   origin: Hash[Symbol, untyped]) -> void
      def initialize(id:, lhs:, rhs:, action:, precedence_override:, origin:)
        @id = id
        @lhs = lhs
        @rhs = rhs.freeze
        @action = action
        @precedence_override = precedence_override
        @origin = IR.deep_freeze(origin)
        freeze
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { id: @id, lhs: @lhs, rhs: @rhs, action: @action&.to_h, prec_override: @precedence_override,
          origin: @origin }
      end
    end

    # Immutable normalized grammar exchanged between pipeline stages.
    class Grammar
      attr_reader :class_name #: String
      attr_reader :superclass #: String?
      attr_reader :start #: String
      attr_reader :expect #: Integer
      attr_reader :options #: grammar_options
      attr_reader :symbols #: Array[GrammarSymbol]
      attr_reader :productions #: Array[Production]
      attr_reader :user_code #: Hash[String, String]
      attr_reader :conversions #: Hash[String, String]
      attr_reader :warnings #: Array[grammar_warning]
      attr_reader :schema_version #: Integer

      # @rbs (class_name: String, superclass: String?, start: String, expect: Integer, options: grammar_options,
      #   symbols: Array[GrammarSymbol], productions: Array[Production], user_code: Hash[String, String],
      #   conversions: Hash[String, String], warnings: Array[grammar_warning], ?schema_version: Integer) -> void
      def initialize(class_name:, superclass:, start:, expect:, options:, symbols:, productions:, user_code:,
                     conversions:, warnings:, schema_version: SCHEMA_VERSION)
        @class_name = class_name.freeze
        @superclass = superclass&.freeze
        @start = start.freeze
        @expect = expect
        @options = IR.deep_freeze(options)
        @symbols = symbols.freeze
        @productions = productions.freeze
        @user_code = IR.deep_freeze(user_code)
        @conversions = IR.deep_freeze(conversions)
        @warnings = IR.deep_freeze(warnings)
        @schema_version = schema_version
        @symbols_by_name = @symbols.to_h { |symbol| [symbol.name, symbol] }.freeze
        @symbols_by_id = @symbols.to_h { |symbol| [symbol.id, symbol] }.freeze
        freeze
      end

      # @rbs (String name) -> GrammarSymbol?
      def symbol(name) = @symbols_by_name[name]
      # @rbs (Integer? id) -> GrammarSymbol?
      def symbol_by_id(id) = @symbols_by_id[id]
      # @rbs () -> Array[GrammarSymbol]
      def terminals = @symbols.select(&:terminal?)
      # @rbs () -> Array[GrammarSymbol]
      def nonterminals = @symbols.select(&:nonterminal?)

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { ibex_ir: "grammar", schema_version: @schema_version, class_name: @class_name, superclass: @superclass,
          start: @start, expect: @expect, options: @options, symbols: @symbols.map(&:to_h),
          productions: @productions.map(&:to_h), user_code: @user_code, conversions: @conversions,
          warnings: @warnings }
      end
    end
  end
end
