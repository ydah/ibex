# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Session-local token metadata used to validate lexical resynchronization.
      class TokenMemo
        ENTRY_BYTES = 32 #: Integer

        attr_reader :tokens #: Array[GreenToken]
        attr_reader :offsets #: Array[Integer]
        attr_reader :states #: Array[Symbol]

        # @rbs (tokens: Array[GreenToken], offsets: Array[Integer], states: Array[Symbol]) -> void
        def initialize(tokens:, offsets:, states:)
          unless tokens.length == offsets.length && offsets.length == states.length
            raise ArgumentError, "token memo arrays must have equal lengths"
          end

          ordered = (0...[offsets.length - 1, 0].max).all? do |index|
            offsets.fetch(index) <= offsets.fetch(index + 1)
          end
          raise ArgumentError, "token memo offsets must be ordered" unless ordered

          @tokens = tokens.dup.freeze
          @offsets = offsets.dup.freeze
          @states = states.dup.freeze
          freeze
        end

        # @rbs (SyntaxNode root, ?states: Array[Symbol]) -> TokenMemo
        def self.from_root(root, states: [])
          tokens = root.tokens.map(&:green)
          offsets = [] #: Array[Integer]
          offset = 0
          tokens.each do |token|
            offsets << offset
            offset += token.full_width
          end
          actual_states = Array.new(tokens.length) { |index| states.fetch(index, :INITIAL) }
          new(tokens: tokens, offsets: offsets, states: actual_states)
        end

        # The first token whose owned full span contains or follows an edit.
        # @rbs (Array[TextEdit] edits) -> Integer?
        def damage_index(edits)
          normalized = TextEdit.normalize(edits)
          edit = normalized.first
          return unless edit

          point = edit.start
          @tokens.each_index do |index|
            start = @offsets.fetch(index)
            finish = start + @tokens.fetch(index).full_width
            return index if point < finish || (start == point && finish == point)
          end
          @tokens.empty? ? nil : @tokens.length - 1
        end

        # @rbs () -> Integer
        def estimated_bytes = @tokens.length * ENTRY_BYTES
      end
    end
  end
end
