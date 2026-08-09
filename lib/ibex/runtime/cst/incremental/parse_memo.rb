# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Parser-state metadata parallel to Green preorder occurrences.
      class ParseMemo
        VERSION = 1 #: Integer
        ENTRY_BYTES = 8 #: Integer

        attr_reader :left_states #: Array[Integer?]
        attr_reader :grammar_digest #: String
        attr_reader :state_count #: Integer
        attr_reader :production_count #: Integer

        # @rbs (left_states: Array[Integer?], grammar_digest: String, state_count: Integer,
        #   production_count: Integer) -> void
        def initialize(left_states:, grammar_digest:, state_count:, production_count:)
          unless left_states.all? { |state| state.nil? || state.between?(0, state_count - 1) }
            raise ArgumentError, "parse memo contains an invalid parser state"
          end

          @left_states = left_states.dup.freeze
          @grammar_digest = grammar_digest.dup.freeze
          @state_count = state_count
          @production_count = production_count
          freeze
        end

        # @rbs (Integer preorder_index) -> Integer?
        def left_state(preorder_index) = @left_states.fetch(preorder_index)

        # @rbs (Integer preorder_index, GreenNode | GreenToken element) -> Array[Integer?]
        def slice(preorder_index, element)
          value = @left_states.slice(preorder_index, element.descendant_count)
          return value if value && value.length == element.descendant_count

          raise IndexError, "parse memo subtree range is outside the preorder state array"
        end

        # @rbs (Hash[Symbol, String | Integer] tables) -> bool
        def compatible?(tables)
          @grammar_digest == tables[:grammar_digest] &&
            @state_count == tables[:state_count] &&
            @production_count == tables[:production_count]
        end

        # @rbs () -> Integer
        def estimated_bytes = @left_states.length * ENTRY_BYTES

        # @rbs () -> Hash[String, Integer | Array[Integer?]]
        def to_h
          { "version" => VERSION, "left_states" => @left_states }.freeze
        end

        # Lightweight construction tree flattened once when a parse completes.
        class Entry
          empty_children = [] # @type var empty_children: Array[Entry]
          EMPTY_CHILDREN = empty_children.freeze #: Array[Entry]

          # @rbs @state: Integer?
          # @rbs @children: Array[Entry]
          # @rbs @segment: Array[Integer?]?

          # @rbs (Integer? state, ?children: Array[Entry], ?segment: Array[Integer?]?) -> void
          def initialize(state, children: EMPTY_CHILDREN, segment: nil)
            @state = state
            @children = if children.empty?
                          EMPTY_CHILDREN
                        elsif children.frozen?
                          children
                        else
                          children.dup.freeze
                        end
            @segment = segment&.then { |values| values.frozen? ? values : values.dup.freeze }
            freeze
          end

          # @rbs (Array[Integer?] output) -> void
          def append_to(output)
            segment = @segment
            if segment
              output.concat(segment)
              return
            end

            output << @state
            @children.each { |child| child.append_to(output) }
          end
        end
      end
    end
  end
end
