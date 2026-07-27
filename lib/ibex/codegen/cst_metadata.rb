# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # Builds the deterministic kind space embedded in CST-aware parser tables.
    class CSTMetadata
      # @rbs!
      #   type kind_map = Hash[String, Integer]
      #   type kinds = {
      #     names: Array[String],
      #     terminal_range: Array[Integer],
      #     nonterminal_range: Array[Integer],
      #     named: kind_map,
      #     named_nonterminals: Hash[Integer, Integer],
      #     trivia: kind_map,
      #     synthetic: kind_map
      #   }
      #   type field_slot = Integer | { index: Integer, extraction: Symbol }
      #   type slot = { node_kind: Integer, node_name: String, fields: Hash[String, field_slot] }
      #   type metadata = {
      #     version: Integer,
      #     trivia_policy: Symbol,
      #     kinds: kinds,
      #     slots: Hash[Integer, slot]
      #   }

      TRIVIA_KINDS = %w[
        whitespace
        newline
        line_comment
        block_comment
        custom_skip
        skipped_tokens
      ].freeze #: Array[String]

      SYNTHETIC_KINDS = %w[
        lexical_error_token
        missing_token
        error_node
        source_file
        synthetic_root
      ].freeze #: Array[String]

      # @rbs @grammar: IR::Grammar
      # @rbs @trivia_policy: Symbol

      # @rbs (IR::Grammar grammar, ?trivia_policy: Symbol | String) -> void
      def initialize(grammar, trivia_policy: :leading)
        @grammar = grammar
        @trivia_policy = normalize_trivia_policy(trivia_policy)
      end

      # Return table-ready CST metadata with stable insertion order.
      # @rbs () -> metadata
      def build
        names = @grammar.symbols.sort_by(&:id).map(&:name)
        named = append_named_kinds(names)
        trivia = append_kinds(names, TRIVIA_KINDS)
        synthetic = append_kinds(names, SYNTHETIC_KINDS)
        terminals = @grammar.terminals.map(&:id)
        nonterminals = @grammar.nonterminals.map(&:id)
        kinds = {
          names: names.freeze,
          terminal_range: half_open_range(terminals),
          nonterminal_range: half_open_range(nonterminals),
          named: named.freeze,
          named_nonterminals: named_nonterminals(named).freeze,
          trivia: trivia.freeze,
          synthetic: synthetic.freeze
        }.freeze #: kinds
        metadata = { # rubocop:disable Style/RedundantAssignment -- preserves the exact record type for Steep.
          version: 1, trivia_policy: @trivia_policy,
          kinds: kinds, slots: slot_metadata(named).freeze
        }.freeze #: metadata
        metadata
      end

      private

      # @rbs (Symbol | String policy) -> Symbol
      def normalize_trivia_policy(policy)
        normalized = policy.to_sym
        normalized = :leading if normalized == :attach
        return normalized if %i[leading balanced drop].include?(normalized)

        raise ArgumentError, "cst_trivia must be :leading, :balanced, or :drop"
      end

      # @rbs (Array[String] names) -> Hash[String, Integer]
      def append_named_kinds(names)
        node_names = @grammar.productions.filter_map { |production| production.node&.fetch(:name) }.uniq.sort
        append_kinds(names, node_names)
      end

      # @rbs (Array[String] names, Array[String] additions) -> Hash[String, Integer]
      def append_kinds(names, additions)
        additions.to_h do |name|
          kind = names.length
          names << name.freeze
          [name.freeze, kind]
        end
      end

      # @rbs (Array[Integer] ids) -> Array[Integer]
      def half_open_range(ids)
        return [0, 0].freeze if ids.empty?

        [ids.min, ids.max + 1].freeze
      end

      # @rbs (Hash[String, Integer] named) -> Hash[Integer, Integer]
      def named_nonterminals(named)
        result = {} #: Hash[Integer, Integer]
        @grammar.productions.each do |production|
          node = production.node
          next unless node

          kind = named.fetch(node.fetch(:name))
          current = result[kind]
          if current && current != production.lhs
            raise ArgumentError, "@node #{node.fetch(:name)} spans multiple nonterminals"
          end

          result[kind] = production.lhs
        end
        result
      end

      # @rbs (Hash[String, Integer] named) -> Hash[Integer, slot]
      def slot_metadata(named)
        @grammar.productions.filter_map do |production|
          node = production.node
          next unless node

          fields = node.fetch(:fields).each_with_index.to_h do |name, index|
            [name, field_slot(index, production.rhs.fetch(index))]
          end.freeze
          [
            production.id,
            {
              node_kind: named.fetch(node.fetch(:name)),
              node_name: node.fetch(:name),
              fields: fields
            }.freeze
          ]
        end.to_h
      end

      # @rbs (Integer index, Integer symbol_id) -> field_slot
      def field_slot(index, symbol_id)
        extraction = repetition_extraction(symbol_id)
        return index unless extraction

        value = { index: index, extraction: extraction } #: field_slot
        value.freeze
      end

      # @rbs (Integer symbol_id) -> Symbol?
      def repetition_extraction(symbol_id)
        origins = @grammar.productions
                          .select { |production| production.lhs == symbol_id }
                          .map { |production| production.origin.fetch(:kind) }.uniq
        return :separated_list if origins == [:separated_list_expansion]
        return :repetition if (origins - %i[star_expansion plus_expansion]).empty? && !origins.empty?

        nil
      end
    end
  end
end
