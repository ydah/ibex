# frozen_string_literal: true

module Ibex
  module IR
    SCHEMA_VERSION = 1

    module_function

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

    # An interned terminal or nonterminal.
    class GrammarSymbol
      attr_reader :id, :name, :kind, :reserved, :precedence, :location

      def initialize(id:, name:, kind:, reserved: false, precedence: nil, location: nil)
        @id = id
        @name = name.freeze
        @kind = kind.to_sym
        @reserved = reserved
        @precedence = IR.deep_freeze(precedence)
        @location = IR.deep_freeze(location)
        freeze
      end

      def terminal? = @kind == :terminal
      def nonterminal? = @kind == :nonterminal

      def to_h
        { id: @id, name: @name, kind: @kind, reserved: @reserved, prec: @precedence, loc: @location }
      end
    end

    # Opaque Ruby semantic action metadata.
    class Action
      attr_reader :code, :location, :named_refs, :context_length

      def initialize(code:, location:, named_refs: [], context_length: 0)
        @code = code.freeze
        @location = IR.deep_freeze(location)
        @named_refs = IR.deep_freeze(named_refs)
        @context_length = context_length
        freeze
      end

      def to_h
        { code: @code, loc: @location, named_refs: @named_refs, context_length: @context_length }
      end
    end

    # A normalized BNF production using symbol ids.
    class Production
      attr_reader :id, :lhs, :rhs, :action, :precedence_override, :origin

      def initialize(id:, lhs:, rhs:, action:, precedence_override:, origin:)
        @id = id
        @lhs = lhs
        @rhs = rhs.freeze
        @action = action
        @precedence_override = precedence_override
        @origin = IR.deep_freeze(origin)
        freeze
      end

      def to_h
        { id: @id, lhs: @lhs, rhs: @rhs, action: @action&.to_h, prec_override: @precedence_override,
          origin: @origin }
      end
    end

    # Immutable normalized grammar exchanged between pipeline stages.
    class Grammar
      attr_reader :class_name, :superclass, :start, :expect, :options, :symbols, :productions, :user_code,
                  :conversions, :warnings, :schema_version

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

      def symbol(name) = @symbols_by_name[name]
      def symbol_by_id(id) = @symbols_by_id[id]
      def terminals = @symbols.select(&:terminal?)
      def nonterminals = @symbols.select(&:nonterminal?)

      def to_h
        { ibex_ir: "grammar", schema_version: @schema_version, class_name: @class_name, superclass: @superclass,
          start: @start, expect: @expect, options: @options, symbols: @symbols.map(&:to_h),
          productions: @productions.map(&:to_h), user_code: @user_code, conversions: @conversions,
          warnings: @warnings }
      end
    end
  end
end
