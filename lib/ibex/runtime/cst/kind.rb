# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Flags cached on Green elements and propagated by Green nodes.
      module Flags
        CONTAINS_ERROR = 1 << 0 #: Integer
        CONTAINS_MISSING = 1 << 1 #: Integer
        CONTAINS_SKIPPED = 1 << 2 #: Integer
        HAS_ANNOTATION = 1 << 3 #: Integer
        SYNTHETIC = 1 << 4 #: Integer
        INCOMPLETE_INPUT = 1 << 5 #: Integer
      end

      # Grammar-specific integer kind names and interval predicates.
      class Kind
        # @rbs!
        #   type kind_map = Hash[String, Integer]
        #   type metadata = {
        #     names: Array[String],
        #     terminal_range: Array[Integer],
        #     nonterminal_range: Array[Integer],
        #     named: kind_map,
        #     named_nonterminals: Hash[Integer, Integer],
        #     trivia: kind_map,
        #     synthetic: kind_map
        #   }

        # @rbs @names: Array[String]
        # @rbs @terminal_range: Array[Integer]
        # @rbs @nonterminal_range: Array[Integer]
        # @rbs @named: Hash[String, Integer]
        # @rbs @named_nonterminals: Hash[Integer, Integer]
        # @rbs @trivia: Hash[String, Integer]
        # @rbs @synthetic: Hash[String, Integer]

        # @rbs (metadata metadata) -> void
        def initialize(metadata)
          @names = metadata.fetch(:names).dup.freeze
          @terminal_range = metadata.fetch(:terminal_range).dup.freeze
          @nonterminal_range = metadata.fetch(:nonterminal_range).dup.freeze
          @named = metadata.fetch(:named).dup.freeze
          @named_nonterminals = metadata.fetch(:named_nonterminals).dup.freeze
          @trivia = metadata.fetch(:trivia).dup.freeze
          @synthetic = metadata.fetch(:synthetic).dup.freeze
          freeze
        end

        # @rbs (Integer kind) -> String
        def name(kind)
          @names.fetch(kind)
        end

        # @rbs (String | Symbol name) -> Integer
        def fetch(name)
          key = name.to_s
          @named[key] || @trivia[key] || @synthetic.fetch(key)
        end

        # @rbs (Integer kind) -> bool
        def terminal?(kind) = within?(@terminal_range, kind)

        # @rbs (Integer kind) -> bool
        def nonterminal?(kind)
          within?(@nonterminal_range, kind) || @named_nonterminals.key?(kind)
        end

        # @rbs (Integer kind) -> bool
        def trivia?(kind) = @trivia.value?(kind)

        # @rbs (Integer kind) -> bool
        def error?(kind)
          kind == @synthetic["lexical_error_token"] || kind == @synthetic["error_node"]
        end

        # Map a named node kind to its physical nonterminal kind.
        # @rbs (Integer kind) -> Integer
        def nonterminal_of(kind)
          @named_nonterminals.fetch(kind, kind)
        end

        private

        # @rbs (Array[Integer] range, Integer kind) -> bool
        def within?(range, kind)
          kind >= range.fetch(0) && kind < range.fetch(1)
        end
      end
    end
  end
end
