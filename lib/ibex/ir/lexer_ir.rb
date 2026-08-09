# frozen_string_literal: true

module Ibex
  module IR
    LEXER_SCHEMA_VERSION = 1
    SUPPORTED_LEXER_SCHEMA_VERSIONS = [LEXER_SCHEMA_VERSION].freeze #: Array[Integer]

    # One normalized, state-scoped lexer rule.
    class LexerRule
      attr_reader :id #: Integer
      attr_reader :state #: String
      attr_reader :kind #: Symbol
      attr_reader :token #: String?
      attr_reader :pattern #: String
      attr_reader :pattern_kind #: Symbol
      attr_reader :options #: String
      attr_reader :action #: String?
      attr_reader :location #: location

      # @rbs (id: Integer, state: String, kind: Symbol, token: String?, pattern: String, pattern_kind: Symbol,
      #   options: String, action: String?, location: location) -> void
      def initialize(id:, state:, kind:, token:, pattern:, pattern_kind:, options:, action:, location:)
        @id = id
        @state = state.freeze
        @kind = kind
        @token = token&.freeze
        @pattern = pattern.freeze
        @pattern_kind = pattern_kind
        @options = options.freeze
        @action = action&.freeze
        @location = IR.deep_freeze(location)
        freeze
      end

      # @rbs () -> Hash[Symbol, lexer_rule_document_value]
      def to_h
        {
          id: @id, state: @state, kind: @kind, token: @token, pattern: @pattern,
          pattern_kind: @pattern_kind, options: @options, action: @action, loc: @location
        }
      end
    end

    # Independently versioned lexer contract embedded by Grammar IR v2.
    class Lexer
      attr_reader :states #: Array[String]
      attr_reader :rules #: Array[LexerRule]
      attr_reader :warnings #: Array[lexer_warning]
      attr_reader :schema_version #: Integer
      attr_reader :source_provenance #: source_provenance?

      # @rbs (states: Array[String], rules: Array[LexerRule], warnings: Array[lexer_warning],
      #   ?schema_version: Integer, ?source_provenance: source_provenance?) -> void
      def initialize(states:, rules:, warnings:, schema_version: LEXER_SCHEMA_VERSION, source_provenance: nil)
        raise ArgumentError, "lexer states must start with INITIAL" unless states.first == "INITIAL"
        raise ArgumentError, "lexer states must be unique" unless states.uniq.length == states.length

        @states = states.map(&:freeze).freeze
        @rules = rules.freeze
        @warnings = IR.deep_freeze(warnings)
        @schema_version = schema_version
        @source_provenance = IR.deep_freeze(source_provenance)
        freeze
      end

      # @rbs () -> Hash[Symbol, lexer_document_value]
      def to_h
        {
          ibex_ir: "lexer", schema_version: @schema_version, initial_state: "INITIAL",
          states: @states, rules: @rules.map(&:to_h), warnings: @warnings,
          source_provenance: @source_provenance
        }
      end
    end
  end
end
