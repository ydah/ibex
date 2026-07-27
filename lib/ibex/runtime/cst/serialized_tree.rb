# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Validated CST serialization document and its reconstructed Red root.
      class SerializedTree
        attr_reader :grammar_digest #: String
        attr_reader :table_format #: Integer
        attr_reader :state_count #: Integer
        attr_reader :production_count #: Integer
        attr_reader :trivia_policy #: Symbol
        attr_reader :kinds #: Kind
        attr_reader :green_root #: GreenNode
        attr_reader :memo #: Hash[String, untyped]?

        # @rbs (grammar_digest: String, table_format: Integer, state_count: Integer,
        #   production_count: Integer, trivia_policy: Symbol, kinds: Kind, green_root: GreenNode,
        #   ?memo: Hash[String, untyped]?) -> void
        def initialize(grammar_digest:, table_format:, state_count:, production_count:, trivia_policy:, kinds:,
                       green_root:, memo: nil)
          @grammar_digest = grammar_digest.dup.freeze
          @table_format = table_format
          @state_count = state_count
          @production_count = production_count
          @trivia_policy = trivia_policy
          @kinds = kinds
          @green_root = green_root
          @memo = memo&.dup&.freeze
          freeze
        end

        # @rbs () -> SyntaxNode
        def syntax_root
          source = SourceText.new(@green_root.to_source)
          SyntaxNode.new(
            green: @green_root, kinds: @kinds, trivia_policy: @trivia_policy, source_text: source
          )
        end
      end
    end
  end
end
