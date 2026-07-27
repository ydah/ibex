# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Immutable result returned by syntax-aware parser entry points.
      class ParseResult
        attr_reader :value #: untyped
        attr_reader :syntax_root #: SyntaxNode
        attr_reader :diagnostics #: Array[untyped]

        # @rbs (value: untyped, syntax_root: SyntaxNode, diagnostics: Array[untyped]) -> void
        def initialize(value:, syntax_root:, diagnostics:)
          @value = value
          @syntax_root = syntax_root
          @diagnostics = diagnostics.dup.freeze
          freeze
        end
      end

      # Syntax-only result used by incremental sessions.
      class SyntaxResult
        attr_reader :syntax_root #: SyntaxNode
        attr_reader :diagnostics #: Array[untyped]
        attr_reader :reused_ratio #: Float

        # @rbs (syntax_root: SyntaxNode, diagnostics: Array[untyped], reused_ratio: Float) -> void
        def initialize(syntax_root:, diagnostics:, reused_ratio:)
          @syntax_root = syntax_root
          @diagnostics = diagnostics.dup.freeze
          @reused_ratio = reused_ratio
          freeze
        end
      end
    end

    ParseResult = CST::ParseResult
    SyntaxResult = CST::SyntaxResult
  end
end
