# frozen_string_literal: true

module Ibex
  module IR
    # A merged LALR item with its lookahead token ids.
    class AutomatonItem
      attr_reader :production #: Integer
      attr_reader :dot #: Integer
      attr_reader :lookaheads #: Array[Integer]

      # @rbs (production: Integer, dot: Integer, lookaheads: Array[Integer]) -> void
      def initialize(production:, dot:, lookaheads:)
        @production = production
        @dot = dot
        @lookaheads = lookaheads.sort.freeze
        freeze
      end

      # @rbs (Grammar grammar) -> Hash[Symbol, untyped]
      def to_h(grammar)
        { production: @production, dot: @dot,
          lookaheads: @lookaheads.map do |id|
            symbol = grammar.symbol_by_id(id) || raise(Ibex::Error, "missing grammar symbol id #{id}")
            symbol.name
          end }
      end
    end

    # A deterministic LALR automaton state.
    class AutomatonState
      attr_reader :id #: Integer
      attr_reader :items #: Array[AutomatonItem]
      attr_reader :transitions #: Hash[Integer, Integer]
      attr_reader :actions #: Hash[Integer, parser_action]
      attr_reader :gotos #: Hash[Integer, Integer]
      attr_reader :default_action #: parser_action?
      attr_reader :conflicts #: Array[conflict]

      # @rbs (id: Integer, items: Array[AutomatonItem], transitions: Hash[Integer, Integer],
      #   actions: Hash[Integer, parser_action], gotos: Hash[Integer, Integer], ?default_action: parser_action?,
      #   ?conflicts: Array[conflict]) -> void
      def initialize(id:, items:, transitions:, actions:, gotos:, default_action: nil, conflicts: [])
        @id = id
        @items = items.freeze
        @transitions = IR.deep_freeze(transitions)
        @actions = IR.deep_freeze(actions)
        @gotos = IR.deep_freeze(gotos)
        @default_action = IR.deep_freeze(default_action)
        @conflicts = IR.deep_freeze(conflicts)
        freeze
      end

      # @rbs (Grammar grammar) -> Hash[Symbol, untyped]
      def to_h(grammar)
        { id: @id, items: @items.map { |item| item.to_h(grammar) },
          transitions: named_keys(@transitions, grammar), actions: named_keys(@actions, grammar),
          gotos: named_keys(@gotos, grammar), default_action: @default_action, conflicts: @conflicts }
      end

      private

      # @rbs (Hash[Integer, untyped] values, Grammar grammar) -> Hash[String, untyped]
      def named_keys(values, grammar)
        values.to_h do |symbol_id, value|
          symbol = grammar.symbol_by_id(symbol_id) || raise(Ibex::Error, "missing grammar symbol id #{symbol_id}")
          [symbol.name, value]
        end
      end
    end

    # Immutable LALR automaton and its source grammar.
    class Automaton
      attr_reader :algorithm #: String
      attr_reader :grammar_digest #: String
      attr_reader :grammar #: Grammar
      attr_reader :states #: Array[AutomatonState]
      attr_reader :conflict_summary #: conflict_summary
      attr_reader :schema_version #: Integer

      # @rbs (grammar: Grammar, states: Array[AutomatonState], conflict_summary: conflict_summary,
      #   ?algorithm: String, ?grammar_digest: String?, ?schema_version: Integer) -> void
      def initialize(grammar:, states:, conflict_summary:, algorithm: "lalr1", grammar_digest: nil,
                     schema_version: SCHEMA_VERSION)
        @algorithm = algorithm.freeze
        @grammar = grammar
        @grammar_digest = (grammar_digest || digest_for(grammar)).freeze
        @states = states.freeze
        @conflict_summary = IR.deep_freeze(conflict_summary)
        @schema_version = schema_version
        freeze
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        { ibex_ir: "automaton", schema_version: @schema_version, algorithm: @algorithm,
          grammar_digest: @grammar_digest, grammar: @grammar.to_h,
          states: @states.map { |state| state.to_h(@grammar) }, conflict_summary: @conflict_summary }
      end

      private

      # @rbs (Grammar grammar) -> String
      def digest_for(grammar)
        require "digest"
        "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(grammar))}"
      end
    end
  end
end
