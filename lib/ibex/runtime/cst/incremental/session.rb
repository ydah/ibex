# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    module CST
      # Raised when incremental parsing cannot preserve its syntax-only contract.
      class IncrementalUnsupportedError < ArgumentError; end

      # A mutable, single-owner session around immutable source and syntax results.
      class IncrementalParseSession
        attr_reader :source_text #: SourceText
        attr_reader :result #: SyntaxResult
        attr_reader :token_memo #: TokenMemo
        attr_reader :last_relex_result #: RelexResult?

        # @rbs (Class parser_class, SourceText source_text, ?resource_limits: ResourceLimits?) -> void
        def initialize(parser_class, source_text, resource_limits: nil)
          unless source_text.is_a?(SourceText)
            raise ArgumentError, "incremental_session requires an Ibex::Runtime::CST::SourceText"
          end

          @resource_limits = resource_limits || ResourceLimits.new #: ResourceLimits
          @parser = parser_class.__send__(:new, resource_limits: @resource_limits) #: Parser
          validate_parser!
          @cache = NodeCache.new #: NodeCache
          @source_text = source_text
          @last_relex_result = nil #: RelexResult?
          @mutex = Mutex.new
          @result, @token_memo = parse_current(0.0)
          enforce_memo_budget!
        end

        # Apply edits expressed against the current source and return syntax only.
        # @rbs (Array[TextEdit] edits) -> SyntaxResult
        def edit(edits)
          @mutex.synchronize do
            normalized = TextEdit.normalize(edits)
            return @result if normalized.empty?

            previous_memo = @token_memo
            @source_text = @source_text.apply(normalized)
            fresh_result, fresh_memo = parse_current(0.0)
            relexed = Relexer.reconcile(previous_memo, fresh_memo, normalized)
            @last_relex_result = relexed
            @token_memo = relexed.memo
            @result = SyntaxResult.new(
              syntax_root: fresh_result.syntax_root,
              diagnostics: fresh_result.diagnostics,
              reused_ratio: relexed.reused_ratio
            )
            enforce_memo_budget!
            @parser.__send__(
              :emit_incremental_event,
              :cst_reuse,
              {
                "stage" => "lexical",
                "reused_tokens" => relexed.reused_count,
                "token_count" => relexed.memo.tokens.length,
                "reused_ratio" => relexed.reused_ratio
              }
            )
            @result
          end
        end

        # Observe parser and incremental runtime events.
        # @rbs () { (Event) -> void } -> Observation::Subscription
        def observe(&observer)
          @parser.observe(&observer)
        end

        # @rbs (Observation::Subscription subscription) -> bool
        def unobserve(subscription)
          @parser.unobserve(subscription)
        end

        private

        # @rbs () -> void
        def validate_parser!
          unless @parser.is_a?(GeneratedLexer)
            raise IncrementalUnsupportedError, "incremental parsing requires a generated lexer"
          end

          tables = @parser.class.parser_tables
          config = tables[:cst]
          unless tables.fetch(:format_version) >= 6 && config.is_a?(Hash)
            raise IncrementalUnsupportedError, "incremental parsing requires a format-v6 Red/Green CST parser"
          end
          return unless config.fetch(:trivia_policy) == :drop

          raise IncrementalUnsupportedError, "incremental parsing does not support drop trivia policy"
        end

        # @rbs (Float reused_ratio) -> [SyntaxResult, TokenMemo]
        def parse_current(reused_ratio)
          parsed = @parser.__send__(:parse_syntax_with_cache, @source_text, @cache)
          result = SyntaxResult.new(
            syntax_root: parsed.syntax_root,
            diagnostics: parsed.diagnostics,
            reused_ratio: reused_ratio
          )
          states = @parser.__send__(:syntax_token_states)
          [result, TokenMemo.from_root(result.syntax_root, states: states)]
        end

        # @rbs () -> void
        def enforce_memo_budget!
          observed = @token_memo.estimated_bytes
          limit = @resource_limits.max_session_memo_bytes
          return unless observed > limit

          @parser.__send__(
            :emit_incremental_event,
            :cst_fallback,
            { "reason" => "memo_budget", "limit" => limit, "observed" => observed }
          )
          @cache.clear
          @token_memo = TokenMemo.from_root(@result.syntax_root)
        end
      end
    end
  end
end
