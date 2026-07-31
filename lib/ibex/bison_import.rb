# frozen_string_literal: true
# rbs_inline: enabled

require_relative "error"
require_relative "ir"

module Ibex
  # Clean-room, nonexecuting import of Bison grammar structure.
  module BisonImport
    DIRECTIVES = {
      "token" => :converted,
      "left" => :converted,
      "right" => :converted,
      "nonassoc" => :converted,
      "precedence" => :converted,
      "start" => :converted,
      "expect" => :converted,
      "expect-rr" => :converted,
      "empty" => :converted,
      "prec" => :converted,
      "nterm" => :recognized_metadata,
      "type" => :recognized_metadata,
      "union" => :recognized_metadata,
      "destructor" => :recognized_metadata,
      "printer" => :recognized_metadata,
      "param" => :recognized_metadata,
      "parse-param" => :recognized_metadata,
      "lex-param" => :recognized_metadata,
      "define" => :recognized_metadata,
      "code" => :recognized_metadata,
      "dprec" => :unsupported,
      "merge" => :unsupported,
      "glr-parser" => :unsupported,
      "nondeterministic-parser" => :unsupported,
      "locations" => :unsupported,
      "initial-action" => :unsupported,
      "language" => :unsupported,
      "skeleton" => :unsupported,
      "require" => :unsupported,
      "output" => :unsupported,
      "file-prefix" => :unsupported,
      "name-prefix" => :unsupported,
      "verbose" => :unsupported,
      "yacc" => :unsupported,
      "debug" => :unsupported,
      "token-table" => :unsupported,
      "no-lines" => :unsupported,
      "header" => :unsupported,
      "defines" => :unsupported,
      "error-verbose" => :unsupported,
      "pure-parser" => :unsupported
    }.freeze #: Hash[String, Symbol]

    FOREIGN_ACTION_SENTINEL = "__ibex_foreign_action_c__" #: String
    STRUCTURAL_STATUS_MARKER = "ibex-bison-structural-status" #: String
    STRUCTURE_NEUTRAL_UNSUPPORTED = %w[
      initial-action locations language skeleton require output file-prefix name-prefix
      verbose yacc debug token-table no-lines header defines error-verbose pure-parser
    ].freeze #: Array[String]

    class BudgetExceeded < Ibex::Error
      attr_reader :details #: Hash[Symbol, untyped]

      # @rbs (Hash[Symbol, untyped] details) -> void
      def initialize(details)
        @details = IR.deep_freeze(details)
        super("(bison-import):1:1: configured import budget was exhausted")
      end
    end

    # One directive occurrence and its original source position.
    class Directive
      attr_reader :name #: String
      attr_reader :status #: Symbol
      attr_reader :line #: Integer
      attr_reader :column #: Integer
      attr_reader :detail #: String

      # @rbs (name: String, status: Symbol, line: Integer, column: Integer, detail: String) -> void
      def initialize(name:, status:, line:, column:, detail:)
        @name = name.freeze
        @status = status
        @line = line
        @column = column
        @detail = detail.freeze
        freeze
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { name: @name, status: @status, line: @line, column: @column, detail: @detail }
      end
    end

    # One opaque C action and its mechanical reference rewrite.
    class Action
      attr_reader :id #: Integer
      attr_reader :line #: Integer
      attr_reader :column #: Integer
      attr_reader :original #: String
      attr_reader :transformed #: String
      attr_reader :encoded #: String

      # @rbs (id: Integer, line: Integer, column: Integer, original: String, transformed: String,
      #   encoded: String) -> void
      def initialize(id:, line:, column:, original:, transformed:, encoded:)
        @id = id
        @line = line
        @column = column
        @original = original.freeze
        @transformed = transformed.freeze
        @encoded = encoded.freeze
        freeze
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        {
          id: @id, line: @line, column: @column,
          original: @original, transformed: @transformed,
          source_encoding: "hex_sentinel"
        }
      end
    end

    # Immutable source artifact and versioned analysis report.
    class Result
      attr_reader :source #: String
      attr_reader :file #: String
      attr_reader :class_name #: String
      attr_reader :directives #: Array[Directive]
      attr_reader :actions #: Array[Action]
      attr_reader :rule_count #: Integer
      attr_reader :bounds #: Hash[Symbol, Integer]

      # @rbs (source: String, file: String, class_name: String, directives: Array[Directive],
      #   actions: Array[Action], rule_count: Integer, bounds: Hash[Symbol, Integer]) -> void
      def initialize(source:, file:, class_name:, directives:, actions:, rule_count:, bounds:)
        @source = source.freeze
        @file = file.freeze
        @class_name = class_name.freeze
        @directives = directives.freeze
        @actions = actions.freeze
        @rule_count = rule_count
        @bounds = IR.deep_freeze(bounds)
        freeze
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        unsupported = @directives.select { |directive| directive.status == :unsupported }
        structural = structural_unsupported
        {
          ibex_report: "bison_import",
          schema_version: 1,
          result: unsupported.empty? ? "imported" : "imported_with_unsupported",
          file: @file,
          class_name: @class_name,
          generated_source: @source,
          directive_contract: DIRECTIVES.sort.to_h,
          directives: @directives.map(&:to_h),
          unsupported: unsupported.map(&:to_h),
          structurally_complete: structural.empty?,
          structural_unsupported: structural.map(&:to_h),
          actions: @actions.map(&:to_h),
          counts: {
            rules: @rule_count,
            actions: @actions.length,
            unsupported_directives: unsupported.length,
            structural_unsupported_directives: structural.length
          },
          bounds: @bounds,
          statement: "C semantic actions are opaque analysis data; Ruby generation is refused."
        }
      end

      # @rbs () -> Array[Directive]
      def structural_unsupported
        @directives.select do |directive|
          directive.status == :unsupported &&
            !STRUCTURE_NEUTRAL_UNSUPPORTED.include?(directive.name)
        end
      end

      # @rbs () -> bool
      def structurally_complete?
        structural_unsupported.empty?
      end
    end

    # @rbs (String source) -> bool
    def bison_source?(source)
      source.lines.count { |line| line.match?(%r{^\s*%%(?:\s|/|$)}) } >= 2
    end
    module_function :bison_source?
  end
end

require_relative "bison_import/tokenizer"
require_relative "bison_import/importer"
