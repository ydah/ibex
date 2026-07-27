# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Result of comparing one fresh lexical pass with the prior token memo.
      class RelexResult
        attr_reader :memo #: TokenMemo
        attr_reader :reused_count #: Integer
        attr_reader :scanned_count #: Integer
        attr_reader :resynchronized_at #: Integer?

        # @rbs (memo: TokenMemo, reused_count: Integer, scanned_count: Integer,
        #   resynchronized_at: Integer?) -> void
        def initialize(memo:, reused_count:, scanned_count:, resynchronized_at:)
          @memo = memo
          @reused_count = reused_count
          @scanned_count = scanned_count
          @resynchronized_at = resynchronized_at
          freeze
        end

        # @rbs () -> Float
        def reused_ratio
          return 0.0 if @memo.tokens.empty?

          @reused_count.fdiv(@memo.tokens.length)
        end
      end

      # Sound Stage-A comparison: scan from the beginning and reuse only exact
      # token/state/boundary matches, then recognize a shifted suffix boundary.
      class Relexer
        # @rbs (TokenMemo previous, TokenMemo current, Array[TextEdit] edits) -> RelexResult
        def self.reconcile(previous, current, edits)
          normalized = TextEdit.normalize(edits)
          return RelexResult.new(memo: current, reused_count: 0, scanned_count: 0, resynchronized_at: nil) if
            normalized.empty?

          damage, delta, resync_boundary = edit_window(normalized)
          old_by_offset = offset_index(previous)
          tokens = current.tokens.dup
          reused, scanned, resynchronized_at = reuse_tokens(
            previous, current, tokens, old_by_offset, damage, delta, resync_boundary
          )
          memo = TokenMemo.new(tokens: tokens, offsets: current.offsets, states: current.states)
          RelexResult.new(
            memo: memo,
            reused_count: reused,
            scanned_count: scanned,
            resynchronized_at: resynchronized_at
          )
        end

        # @rbs (Array[TextEdit] edits) -> [Integer, Integer, Integer]
        def self.edit_window(edits)
          delta = edits.sum { |edit| edit.insert_text.bytesize - edit.delete_length }
          prefix_delta = edits.take(edits.length - 1).sum do |edit|
            edit.insert_text.bytesize - edit.delete_length
          end
          last_edit = edits.last
          [edits.first.start, delta, last_edit.start + prefix_delta + last_edit.insert_text.bytesize]
        end

        # @rbs (TokenMemo memo) -> Hash[Integer, Integer]
        def self.offset_index(memo)
          result = {} #: Hash[Integer, Integer]
          memo.offsets.each_with_index { |offset, index| result[offset] = index }
          result
        end

        # @rbs (TokenMemo previous, TokenMemo current, Array[GreenToken] tokens,
        #   Hash[Integer, Integer] old_by_offset, Integer damage, Integer delta, Integer resync_boundary) ->
        #   [Integer, Integer, Integer?]
        def self.reuse_tokens(previous, current, tokens, old_by_offset, damage, delta, resync_boundary)
          reused = 0
          scanned = 0
          current.tokens.each_index do |index|
            new_offset = current.offsets.fetch(index)
            suffix = reusable_suffix(
              previous, current, index, new_offset, delta, resync_boundary, old_by_offset
            )
            if suffix
              old_index, length = suffix
              copy_suffix(tokens, previous.tokens, index, old_index, length)
              return [reused + length, scanned, index]
            end

            old_index = index if new_offset < damage
            scanned += 1
            next unless old_index
            next unless reusable_token?(previous, old_index, current, index)

            tokens[index] = previous.tokens.fetch(old_index)
            reused += 1
          end
          [reused, scanned, nil]
        end

        # @rbs (TokenMemo previous, TokenMemo current, Integer index, Integer new_offset, Integer delta,
        #   Integer boundary, Hash[Integer, Integer] old_by_offset) -> [Integer, Integer]?
        def self.reusable_suffix(previous, current, index, new_offset, delta, boundary, old_by_offset)
          return if new_offset < boundary

          old_index = old_by_offset[new_offset - delta]
          return unless old_index

          length = current.tokens.length - index
          return unless length == previous.tokens.length - old_index
          return unless previous.states.fetch(old_index) == current.states.fetch(index)

          [old_index, length]
        end

        # @rbs (Array[GreenToken] target, Array[GreenToken] source, Integer target_index,
        #   Integer source_index, Integer length) -> void
        def self.copy_suffix(target, source, target_index, source_index, length)
          length.times do |relative|
            target[target_index + relative] = source.fetch(source_index + relative)
          end
        end

        # @rbs (TokenMemo previous, Integer old_index, TokenMemo current, Integer new_index) -> bool
        def self.reusable_token?(previous, old_index, current, new_index)
          previous.states.fetch(old_index) == current.states.fetch(new_index) &&
            previous.tokens.fetch(old_index) == current.tokens.fetch(new_index)
        end
        private_class_method :edit_window, :offset_index, :reuse_tokens, :reusable_suffix, :copy_suffix,
                             :reusable_token?
      end
    end
  end
end
