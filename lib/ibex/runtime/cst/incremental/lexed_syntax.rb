# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # One complete generated-lexer pass, including the explicit EOF token.
      class LexedSyntax
        attr_reader :raw_tokens #: Array[Array[untyped]]
        attr_reader :memo #: TokenMemo

        # @rbs (raw_tokens: Array[Array[untyped]], memo: TokenMemo) -> void
        def initialize(raw_tokens:, memo:)
          raise ArgumentError, "raw and Green token counts differ" unless raw_tokens.length == memo.tokens.length

          @raw_tokens = raw_tokens.map { |token| token.dup.freeze }.freeze
          @memo = memo
          freeze
        end

        # @rbs (TokenMemo replacement) -> LexedSyntax
        def with_memo(replacement)
          LexedSyntax.new(raw_tokens: @raw_tokens, memo: replacement)
        end
      end
    end
  end
end
