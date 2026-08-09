# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Immutable result returned by syntax-aware parser entry points.
      class ParseResult
        attr_reader :value #: Object
        attr_reader :syntax_root #: SyntaxNode
        attr_reader :diagnostics #: Array[Object]

        # @rbs (value: Object, syntax_root: SyntaxNode, diagnostics: Array[Object]) -> void
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
        attr_reader :diagnostics #: Array[Object]
        attr_reader :reused_ratio #: Float

        # @rbs (syntax_root: SyntaxNode, diagnostics: Array[Object], reused_ratio: Float) -> void
        def initialize(syntax_root:, diagnostics:, reused_ratio:)
          @syntax_root = syntax_root
          @diagnostics = diagnostics.dup.freeze
          @reused_ratio = reused_ratio
          freeze
        end
      end
    end

    ParseResult = CST::ParseResult #: singleton(CST::ParseResult)
    SyntaxResult = CST::SyntaxResult #: singleton(CST::SyntaxResult)
  end
end
