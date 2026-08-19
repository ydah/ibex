# frozen_string_literal: true

require_relative "../configuration"

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
        @lookaheads = lookaheads.sort.dup.freeze
        freeze
      end

      # @rbs (Grammar grammar) -> Hash[Symbol, Object?]
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
        @items = items.dup.freeze
        @transitions = IR.deep_freeze(transitions)
        @actions = IR.deep_freeze(actions)
        @gotos = IR.deep_freeze(gotos)
        @default_action = IR.deep_freeze(default_action)
        @conflicts = IR.deep_freeze(conflicts)
        freeze
      end

      # @rbs (Grammar grammar) -> Hash[Symbol, Object?]
      def to_h(grammar)
        { id: @id, items: @items.map { |item| item.to_h(grammar) },
          transitions: named_keys(@transitions, grammar), actions: named_keys(@actions, grammar),
          gotos: named_keys(@gotos, grammar), default_action: @default_action, conflicts: @conflicts }
      end

      private

      # @rbs (Hash[Integer, Object?] values, Grammar grammar) -> Hash[String, Object?]
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
      attr_reader :entry_states #: Hash[String, Integer]
      attr_reader :conflict_summary #: conflict_summary
      attr_reader :schema_version #: Integer
      attr_reader :entry_construction #: String

      # @rbs (grammar: Grammar, states: Array[AutomatonState], conflict_summary: conflict_summary,
      #   ?algorithm: String, ?grammar_digest: String?, ?entry_states: Hash[String, Integer]?,
      #   ?entry_construction: String) -> void
      def initialize(grammar:, states:, conflict_summary:, algorithm: "lalr1", grammar_digest: nil,
                     entry_states: nil, entry_construction: "shared")
        initialize_current(
          grammar: grammar, states: states, conflict_summary: conflict_summary, algorithm: algorithm,
          grammar_digest: grammar_digest, entry_states: entry_states, entry_construction: entry_construction
        )
      end

      # @rbs (grammar: Grammar, states: Array[AutomatonState], conflict_summary: conflict_summary,
      #   algorithm: String, grammar_digest: String?, entry_states: Hash[String, Integer]?,
      #   entry_construction: String) -> void
      def initialize_current(grammar:, states:, conflict_summary:, algorithm:, grammar_digest:, entry_states:,
                             entry_construction:)
        unless grammar.schema_version == SCHEMA_VERSION
          raise Ibex::Error, "automaton requires the current Grammar IR format"
        end

        @algorithm = algorithm.dup.freeze
        @grammar = grammar
        expected_digest = digest_for(grammar)
        if grammar_digest && grammar_digest != expected_digest
          raise Ibex::Error,
                "(ir):1:1: $.grammar_digest does not match the embedded grammar; expected #{expected_digest.inspect}"
        end
        @grammar_digest = (grammar_digest || expected_digest).dup.freeze
        @states = states.dup.freeze
        @entry_states = IR.deep_freeze(entry_states || { grammar.start => 0 })
        validate_entry_states
        @conflict_summary = IR.deep_freeze(conflict_summary)
        @schema_version = SCHEMA_VERSION
        @entry_construction = validate_entry_construction(entry_construction)
        validate_parser_contract
        freeze
      end
      private :initialize_current

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        value = { ibex_ir: "automaton", schema_version: @schema_version, algorithm: @algorithm,
                  grammar_digest: @grammar_digest, grammar: @grammar.to_h,
                  states: @states.map { |state| state.to_h(@grammar) },
                  conflict_summary: @conflict_summary } #: Hash[Symbol, Object?]
        value[:entry_states] = @entry_states unless @entry_states == { @grammar.start => 0 }
        value[:entry_construction] = @entry_construction
        value
      end

      private

      # @rbs () -> void
      def validate_entry_states
        ordered = @grammar.starts.select { |name| @entry_states.key?(name) }
        unless @entry_states.any? && @entry_states.keys == ordered
          raise Ibex::Error, "(ir):1:1: automaton entry states must be an ordered subset of grammar starts"
        end

        @entry_states.each do |name, state|
          next if state.between?(0, @states.length - 1)

          raise Ibex::Error, "(ir):1:1: entry #{name} references missing state #{state}"
        end
      end

      # @rbs (Grammar grammar) -> String
      def digest_for(grammar)
        require "digest"
        "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(grammar))}"
      end

      # @rbs (String value) -> String
      def validate_entry_construction(value)
        unless Configuration::Registry.parser_setting_values(:entries).map(&:to_s).include?(value)
          raise Ibex::Error, "entry construction must be shared or isolated"
        end

        value.dup.freeze
      end

      # @rbs () -> void
      def validate_parser_contract
        contract = @grammar.parser_contract
        validate_parser_algorithm(contract)
        validate_parser_entries(contract)
      end

      # @rbs (ParserContract contract) -> void
      def validate_parser_algorithm(contract)
        selected_algorithm = { "lalr1" => :lalr, "ielr1" => :ielr }.fetch(@algorithm, @algorithm.to_sym)
        return unless contract.algorithm.explicit && contract.algorithm.value != selected_algorithm

        raise Ibex::Error, "automaton algorithm conflicts with the embedded parser contract"
      end

      # @rbs (ParserContract contract) -> void
      def validate_parser_entries(contract)
        return unless contract.entries.explicit && contract.entries.value.to_s != @entry_construction

        raise Ibex::Error, "automaton entry construction conflicts with the embedded parser contract"
      end
    end
  end
end
