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
      attr_reader :entry_states #: Hash[String, Integer]
      attr_reader :conflict_summary #: conflict_summary
      attr_reader :schema_version #: Integer
      # @rbs skip
      attr_reader :entry_construction #: String?

      # @rbs (grammar: Grammar, states: Array[AutomatonState], conflict_summary: conflict_summary,
      #   ?algorithm: String, ?grammar_digest: String?, ?schema_version: Integer,
      #   ?entry_states: Hash[String, Integer]?) -> void
      def initialize(grammar:, states:, conflict_summary:, algorithm: "lalr1", grammar_digest: nil,
                     schema_version: SCHEMA_VERSION, entry_states: nil)
        initialize_versioned(
          grammar: grammar, states: states, conflict_summary: conflict_summary, algorithm: algorithm,
          grammar_digest: grammar_digest, schema_version: schema_version, entry_states: entry_states,
          entry_construction: nil
        )
      end

      # @rbs skip
      def self.v3(grammar:, states:, conflict_summary:, entry_construction:, algorithm: "lalr1", grammar_digest: nil,
                  entry_states: nil)
        automaton = allocate
        automaton.send(
          :initialize_versioned,
          grammar: grammar, states: states, conflict_summary: conflict_summary, algorithm: algorithm,
          grammar_digest: grammar_digest, schema_version: LATEST_SCHEMA_VERSION, entry_states: entry_states,
          entry_construction: entry_construction
        )
        automaton
      end

      # @rbs skip
      def initialize_versioned(grammar:, states:, conflict_summary:, algorithm:, grammar_digest:, schema_version:,
                               entry_states:, entry_construction:)
        unless SUPPORTED_SCHEMA_VERSIONS.include?(schema_version)
          raise Ibex::Error, "unsupported automaton schema_version #{schema_version.inspect}"
        end

        if schema_version >= 2 && grammar.schema_version < schema_version
          grammar = Migration.to_version(grammar, to: schema_version)
        end
        raise Ibex::Error, "automaton migration did not produce a grammar" unless grammar.is_a?(Grammar)
        unless grammar.schema_version == schema_version
          raise Ibex::Error,
                "automaton schema_version #{schema_version} requires Grammar IR v#{schema_version}, " \
                "got v#{grammar.schema_version}"
        end

        @algorithm = algorithm.freeze
        @grammar = grammar
        expected_digest = digest_for(grammar)
        if schema_version >= 3 && grammar_digest && grammar_digest != expected_digest
          raise Ibex::Error,
                "(ir):1:1: $.grammar_digest does not match the embedded grammar; expected #{expected_digest.inspect}"
        end
        @grammar_digest = (grammar_digest || expected_digest).freeze
        @states = states.freeze
        @entry_states = IR.deep_freeze(entry_states || { grammar.start => 0 })
        validate_entry_states
        @conflict_summary = IR.deep_freeze(conflict_summary)
        @schema_version = schema_version
        @entry_construction = validate_entry_construction(schema_version, entry_construction)
        validate_parser_contract
        freeze
      end
      private :initialize_versioned

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        value = { ibex_ir: "automaton", schema_version: @schema_version, algorithm: @algorithm,
                  grammar_digest: @grammar_digest, grammar: @grammar.to_h,
                  states: @states.map { |state| state.to_h(@grammar) },
                  conflict_summary: @conflict_summary } #: Hash[Symbol, untyped]
        value[:entry_states] = @entry_states unless @entry_states == { @grammar.start => 0 }
        value[:entry_construction] = @entry_construction if @schema_version >= 3
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

      # @rbs skip
      def validate_entry_construction(schema_version, value)
        if schema_version >= 3
          unless %w[shared isolated unknown].include?(value)
            raise Ibex::Error, "Automaton IR v3 requires shared, isolated, or unknown entry construction"
          end

          return value&.dup&.freeze
        end
        raise Ibex::Error, "entry construction requires Automaton IR schema_version 3" if value

        nil
      end

      # @rbs skip
      def validate_parser_contract
        return unless @schema_version >= 3

        contract = @grammar.parser_contract || raise(Ibex::Error, "Grammar IR v3 parser contract is missing")
        selected_algorithm = { "lalr1" => :lalr, "ielr1" => :ielr }.fetch(@algorithm, @algorithm.to_sym)
        if contract.algorithm.explicit && contract.algorithm.value != selected_algorithm
          raise Ibex::Error, "automaton algorithm conflicts with the embedded parser contract"
        end
        if contract.entries.explicit && contract.entries.value.to_s != @entry_construction
          raise Ibex::Error, "automaton entry construction conflicts with the embedded parser contract"
        end
        return unless @entry_construction == "unknown"

        unavailable = @grammar.migration&.fetch(:unavailable, []) || []
        return if unavailable.include?("effective_parser_entries") && !contract.entries.explicit

        raise Ibex::Error,
              "(ir):1:1: $.entry_construction may be unknown only for migrated unavailable history"
      end
    end
  end
end
