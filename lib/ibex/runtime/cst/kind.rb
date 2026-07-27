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
        #   type field_slot = Integer | { index: Integer, extraction: Symbol }
        #   type slot = { node_kind: Integer, node_name: String, fields: Hash[String, field_slot] }
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
        # @rbs @field_slots: Hash[Integer, Hash[String, field_slot]]

        # @rbs (metadata metadata, ?slots: Hash[Integer, slot]) -> void
        def initialize(metadata, slots: {})
          @names = metadata.fetch(:names).dup.freeze
          @terminal_range = metadata.fetch(:terminal_range).dup.freeze
          @nonterminal_range = metadata.fetch(:nonterminal_range).dup.freeze
          @named = metadata.fetch(:named).dup.freeze
          @named_nonterminals = metadata.fetch(:named_nonterminals).dup.freeze
          @trivia = metadata.fetch(:trivia).dup.freeze
          @synthetic = metadata.fetch(:synthetic).dup.freeze
          @field_slots = build_field_slots(slots)
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

        # Return the named field-to-physical-slot mapping for a kind.
        # @rbs (Integer kind) -> Hash[String, field_slot]
        def fields(kind) = @field_slots.fetch(kind, EMPTY_FIELDS)

        private

        empty_fields = {} #: Hash[String, field_slot]
        EMPTY_FIELDS = empty_fields.freeze
        private_constant :EMPTY_FIELDS

        # @rbs (Hash[Integer, slot] slots) -> Hash[Integer, Hash[String, field_slot]]
        def build_field_slots(slots)
          values = {} #: Hash[Integer, Hash[String, field_slot]]
          slots.each_value do |slot|
            kind = slot.fetch(:node_kind)
            fields = slot.fetch(:fields).to_h do |name, field_slot|
              index = field_slot.is_a?(Hash) ? field_slot.fetch(:index) : field_slot
              [name, index]
            end.freeze
            previous = values[kind]
            raise ArgumentError, "conflicting CST fields for kind #{kind}" if previous && previous != fields

            values[kind] = fields
          end
          values.freeze
        end

        # @rbs (Array[Integer] range, Integer kind) -> bool
        def within?(range, kind)
          kind >= range.fetch(0) && kind < range.fetch(1)
        end
      end
    end
  end
end
