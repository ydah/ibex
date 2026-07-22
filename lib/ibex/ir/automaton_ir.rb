# frozen_string_literal: true

module Ibex
  module IR
    # A merged LALR item with its lookahead token ids.
    class AutomatonItem
      attr_reader :production, :dot, :lookaheads

      def initialize(production:, dot:, lookaheads:)
        @production = production
        @dot = dot
        @lookaheads = lookaheads.sort.freeze
        freeze
      end

      def to_h(grammar)
        { production: @production, dot: @dot,
          lookaheads: @lookaheads.map { |id| grammar.symbol_by_id(id).name } }
      end
    end

    # A deterministic LALR automaton state.
    class AutomatonState
      attr_reader :id, :items, :transitions, :actions, :gotos, :default_action, :conflicts

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

      def to_h(grammar)
        { id: @id, items: @items.map { |item| item.to_h(grammar) },
          transitions: named_keys(@transitions, grammar), actions: named_keys(@actions, grammar),
          gotos: named_keys(@gotos, grammar), default_action: @default_action, conflicts: @conflicts }
      end

      private

      def named_keys(values, grammar)
        values.to_h { |symbol_id, value| [grammar.symbol_by_id(symbol_id).name, value] }
      end
    end

    # Immutable LALR automaton and its source grammar.
    class Automaton
      attr_reader :algorithm, :grammar_digest, :grammar, :states, :conflict_summary, :schema_version

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

      def to_h
        { ibex_ir: "automaton", schema_version: @schema_version, algorithm: @algorithm,
          grammar_digest: @grammar_digest, grammar: @grammar.to_h,
          states: @states.map { |state| state.to_h(@grammar) }, conflict_summary: @conflict_summary }
      end

      private

      def digest_for(grammar)
        require "digest"
        "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(grammar))}"
      end
    end
  end
end
