# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # A Green nonterminal that can replace its old LR shift/reduce sequence.
      class ReusableSubtree
        attr_reader :green #: GreenNode
        attr_reader :lhs #: Integer
        attr_reader :left_state #: Integer
        attr_reader :left_states #: Array[Integer?]
        attr_reader :previous_trailing #: Array[GreenTrivia]

        # @rbs (green: GreenNode, lhs: Integer, left_state: Integer, left_states: Array[Integer?],
        #   previous_trailing: Array[GreenTrivia]) -> void
        def initialize(green:, lhs:, left_state:, left_states:, previous_trailing:)
          @green = green
          @lhs = lhs
          @left_state = left_state
          @left_states = left_states.dup.freeze
          @previous_trailing = previous_trailing.dup.freeze
          freeze
        end
      end

      # A state-aware token source that substitutes validated old subtrees.
      class Blender
        class Candidate
          attr_reader :entry #: ReusableSubtree
          attr_reader :token_count #: Integer

          # @rbs (entry: ReusableSubtree, token_count: Integer) -> void
          def initialize(entry:, token_count:)
            @entry = entry
            @token_count = token_count
            freeze
          end
        end

        UNSAFE_FLAGS = Flags::CONTAINS_ERROR | Flags::CONTAINS_MISSING | Flags::CONTAINS_SKIPPED #: Integer

        attr_reader :reused_descendants #: Integer
        attr_reader :decomposed_nodes #: Integer
        attr_reader :fallback_reason #: Symbol?

        # @rbs @old_root: SyntaxNode
        # @rbs @parse_memo: ParseMemo
        # @rbs @lexed: LexedSyntax
        # @rbs @edits: Array[TextEdit]
        # @rbs @max_decomposed_nodes: Integer
        # @rbs @enabled: bool
        # @rbs @candidates: Hash[Integer, Array[Candidate]]
        # @rbs @new_offsets: Hash[Integer, Integer]
        # @rbs @old_tokens: Array[GreenToken]
        # @rbs @token_index: Integer

        # @rbs (old_root: SyntaxNode, parse_memo: ParseMemo, lexed: LexedSyntax, edits: Array[TextEdit],
        #   max_decomposed_nodes: Integer, ?enabled: bool) -> void
        def initialize(old_root:, parse_memo:, lexed:, edits:, max_decomposed_nodes:, enabled: true)
          @old_root = old_root
          @parse_memo = parse_memo
          @lexed = lexed
          @edits = TextEdit.normalize(edits)
          @max_decomposed_nodes = max_decomposed_nodes
          @enabled = enabled
          @candidates = {} #: Hash[Integer, Array[Candidate]]
          @new_offsets = offset_index(@lexed.memo.offsets)
          @old_tokens = @old_root.tokens.map(&:green)
          @token_index = 0
          @reused_descendants = 0
          @decomposed_nodes = 0
          @fallback_reason = nil #: Symbol?
          build_candidates if @enabled && reusable_root?
        end

        # Return the next token or a whole nonterminal valid in the current LR state.
        # @rbs (Integer state) -> (Array[Object?] | ReusableSubtree | false)
        def next_for_state(state)
          candidates = @candidates[@token_index]
          candidate = candidates&.find { |item| item.entry.left_state == state }
          if candidate
            @token_index += candidate.token_count
            @reused_descendants += candidate.entry.green.descendant_count
            return candidate.entry
          end

          token = @lexed.raw_tokens[@token_index]
          return false unless token

          @token_index += 1
          token
        end

        # @rbs () -> Integer
        def token_count = @lexed.memo.tokens.length

        private

        # @rbs () -> bool
        def reusable_root?
          @old_root.green.flags.nobits?(UNSAFE_FLAGS) &&
            @parse_memo.left_states.length == @old_root.green.descendant_count
        end

        # @rbs () -> void
        def build_candidates
          walk(@old_root.green, offset: 0, preorder: 0, token_index: 0)
          @candidates.each_value do |values|
            values.sort_by! { |candidate| -candidate.entry.green.descendant_count }
          end
        rescue ResourceLimitError
          @candidates.clear
          @fallback_reason = :decomposition_budget
        end

        # @rbs (GreenNode | GreenToken element, offset: Integer, preorder: Integer, token_index: Integer) ->
        #   [Integer, Integer, Integer]
        def walk(element, offset:, preorder:, token_index:)
          next_preorder = preorder + 1
          return [next_preorder, offset + element.full_width, token_index + 1] if element.is_a?(GreenToken)

          consume_decomposition_budget!
          start_token = token_index
          element.children.each do |child|
            next_preorder, offset, token_index = walk(
              child, offset: offset, preorder: next_preorder, token_index: token_index
            )
          end
          add_candidate(element, preorder, offset - element.full_width, start_token, token_index)
          [next_preorder, offset, token_index]
        end

        # @rbs (GreenNode node, Integer preorder, Integer old_offset, Integer start_token, Integer end_token) -> void
        def add_candidate(node, preorder, old_offset, start_token, end_token)
          return unless reusable_node?(node, old_offset)

          new_offset = translated_offset(old_offset)
          new_index = @new_offsets[new_offset]
          token_count = end_token - start_token
          return unless new_index && token_count.positive?
          return unless matching_tokens?(start_token, new_index, token_count)
          return unless matching_follow_token?(end_token, new_index + token_count)

          left_state = @parse_memo.left_state(preorder)
          return unless left_state

          entry = ReusableSubtree.new(
            green: node,
            lhs: @old_root.kinds.nonterminal_of(node.kind),
            left_state: left_state,
            left_states: @parse_memo.slice(preorder, node),
            previous_trailing: previous_trailing(new_index)
          )
          empty = [] #: Array[Candidate]
          (@candidates[new_index] ||= empty) << Candidate.new(entry: entry, token_count: token_count)
        end

        # @rbs (GreenNode node, Integer old_offset) -> bool
        def reusable_node?(node, old_offset)
          node.full_width.positive? &&
            node.flags.nobits?(UNSAFE_FLAGS) &&
            @old_root.kinds.nonterminal?(node.kind) &&
            outside_damage?(old_offset, old_offset + node.full_width)
        end

        # @rbs (Integer start_offset, Integer finish_offset) -> bool
        def outside_damage?(start_offset, finish_offset)
          @edits.none? do |edit|
            edit_finish = edit.start + edit.delete_length
            if edit.delete_length.zero?
              edit.start >= start_offset && edit.start < finish_offset
            else
              edit.start < finish_offset && edit_finish > start_offset
            end
          end
        end

        # @rbs (Integer old_offset) -> Integer
        def translated_offset(old_offset)
          delta = @edits.sum do |edit|
            edit.start + edit.delete_length <= old_offset ? edit.insert_text.bytesize - edit.delete_length : 0
          end
          old_offset + delta
        end

        # @rbs (Integer old_index, Integer new_index, Integer count) -> bool
        def matching_tokens?(old_index, new_index, count)
          count.times.all? do |relative|
            @old_tokens.fetch(old_index + relative).equal?(@lexed.memo.tokens[new_index + relative])
          end
        end

        # @rbs (Integer old_index, Integer new_index) -> bool
        def matching_follow_token?(old_index, new_index)
          old_follow = @old_tokens[old_index]
          new_follow = @lexed.memo.tokens[new_index]
          old_follow && new_follow ? old_follow.equal?(new_follow) : false
        end

        # @rbs (Integer token_index) -> Array[GreenTrivia]
        def previous_trailing(token_index)
          location = @lexed.raw_tokens.fetch(token_index).fetch(2)
          return [] unless location.is_a?(Hash)

          value = location[:cst_previous_trailing]
          value.is_a?(Array) ? value.grep(GreenTrivia) : []
        end

        # @rbs (Array[Integer] offsets) -> Hash[Integer, Integer]
        def offset_index(offsets)
          result = {} #: Hash[Integer, Integer]
          offsets.each_with_index { |offset, index| result[offset] ||= index }
          result
        end

        # @rbs () -> void
        def consume_decomposition_budget!
          @decomposed_nodes += 1
          return if @decomposed_nodes <= @max_decomposed_nodes

          raise ResourceLimitError.new(
            resource: :incremental_decomposed_nodes,
            limit: @max_decomposed_nodes,
            observed: @decomposed_nodes,
            state: nil,
            location: nil
          )
        end
      end
    end
  end
end
