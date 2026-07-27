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
        attr_reader :parse_memo #: ParseMemo
        attr_reader :last_relex_result #: RelexResult?
        attr_reader :last_blender #: Blender?

        # @rbs @resource_limits: ResourceLimits
        # @rbs @parser: Parser
        # @rbs @cache: NodeCache
        # @rbs @blender_enabled: bool
        # @rbs @mutex: Mutex

        # @rbs (Class parser_class, SourceText source_text, ?resource_limits: ResourceLimits?, ?blender: bool) -> void
        def initialize(parser_class, source_text, resource_limits: nil, blender: true)
          unless source_text.is_a?(SourceText)
            raise ArgumentError, "incremental_session requires an Ibex::Runtime::CST::SourceText"
          end

          @resource_limits = resource_limits || ResourceLimits.new #: ResourceLimits
          @parser = parser_class.__send__(:new, resource_limits: @resource_limits) #: Parser
          validate_parser!
          @cache = NodeCache.new #: NodeCache
          @source_text = source_text
          @last_relex_result = nil #: RelexResult?
          @last_blender = nil #: Blender?
          @blender_enabled = blender
          @mutex = Mutex.new
          @result, @token_memo, @parse_memo = parse_current(0.0)
          enforce_memo_budget!
        end

        # Apply edits expressed against the current source and return syntax only.
        # @rbs (Array[TextEdit] edits) -> SyntaxResult
        def edit(edits)
          @mutex.synchronize { edit_locked(TextEdit.normalize(edits)) }
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

        # @rbs (Array[TextEdit] edits) -> SyntaxResult
        def edit_locked(edits)
          return @result if edits.empty?

          previous_memo = @token_memo
          previous_root = @result.syntax_root
          previous_parse_memo = @parse_memo
          @source_text = @source_text.apply(edits)
          lexed = scan_current
          return finish_full_fallback(previous_memo, edits, :lexical_error) unless lexed

          relexed = Relexer.reconcile(previous_memo, lexed.memo, edits)
          blender = build_blender(previous_root, previous_parse_memo, lexed.with_memo(relexed.memo), edits)
          finish_blended_edit(relexed, blender)
        end

        # @rbs () -> LexedSyntax?
        def scan_current
          @parser.__send__(:scan_syntax_with_cache, @source_text, @cache)
        rescue ParseError
          nil
        end

        # @rbs (SyntaxNode old_root, ParseMemo old_memo, LexedSyntax lexed, Array[TextEdit] edits) -> Blender
        def build_blender(old_root, old_memo, lexed, edits)
          Blender.new(
            old_root: old_root,
            parse_memo: old_memo,
            lexed: lexed,
            edits: edits,
            max_decomposed_nodes: @resource_limits.max_incremental_decomposed_nodes,
            enabled: @blender_enabled
          )
        end

        # @rbs (RelexResult relexed, Blender blender) -> SyntaxResult
        def finish_blended_edit(relexed, blender)
          @last_relex_result = relexed
          @last_blender = blender
          parsed = @parser.__send__(:parse_syntax_token_source, blender, @cache)
          reused_ratio = blender_reused_ratio(blender, parsed.syntax_root.green, relexed)
          @token_memo = relexed.memo
          @parse_memo = @parser.__send__(:syntax_parse_memo) || empty_parse_memo(parsed.syntax_root.green)
          @result = SyntaxResult.new(
            syntax_root: parsed.syntax_root,
            diagnostics: parsed.diagnostics,
            reused_ratio: reused_ratio
          )
          report_blender_fallback(blender)
          enforce_memo_budget!
          emit_reuse_event(blender, relexed, reused_ratio)
          @result
        end

        # @rbs (Blender blender, GreenNode root, RelexResult relexed) -> Float
        def blender_reused_ratio(blender, root, relexed)
          return relexed.reused_ratio unless @blender_enabled

          blender.reused_descendants.fdiv(root.descendant_count)
        end

        # @rbs (Blender blender, RelexResult relexed, Float reused_ratio) -> void
        def emit_reuse_event(blender, relexed, reused_ratio)
          @parser.__send__(
            :emit_incremental_event,
            :cst_reuse,
            {
              "stage" => blender.reused_descendants.positive? ? "subtree" : "lexical",
              "reused_tokens" => relexed.reused_count,
              "token_count" => relexed.memo.tokens.length,
              "reused_ratio" => reused_ratio
            }
          )
        end

        # @rbs () -> void
        def validate_parser!
          unless @parser.is_a?(GeneratedLexer)
            raise IncrementalUnsupportedError, "incremental parsing requires a generated lexer"
          end

          tables = @parser.__send__(:parser_tables) #: Hash[Symbol, untyped]
          config = tables[:cst]
          unless tables.fetch(:format_version) >= 6 && config.is_a?(Hash)
            raise IncrementalUnsupportedError, "incremental parsing requires a format-v6 Red/Green CST parser"
          end
          return unless config.fetch(:trivia_policy) == :drop

          raise IncrementalUnsupportedError, "incremental parsing does not support drop trivia policy"
        end

        # @rbs (Float reused_ratio) -> [SyntaxResult, TokenMemo, ParseMemo]
        def parse_current(reused_ratio)
          parsed = @parser.__send__(:parse_syntax_with_cache, @source_text, @cache)
          result = SyntaxResult.new(
            syntax_root: parsed.syntax_root,
            diagnostics: parsed.diagnostics,
            reused_ratio: reused_ratio
          )
          states = @parser.__send__(:syntax_token_states)
          parse_memo = @parser.__send__(:syntax_parse_memo) || empty_parse_memo(result.syntax_root.green)

          [result, TokenMemo.from_root(result.syntax_root, states: states), parse_memo]
        end

        # Error trees cannot be reused, but retain position-aligned disposable memo storage.
        # @rbs (GreenNode root) -> ParseMemo
        def empty_parse_memo(root)
          tables = @parser.__send__(:parser_tables) #: Hash[Symbol, untyped]
          ParseMemo.new(
            left_states: Array.new(root.descendant_count),
            grammar_digest: tables.fetch(:grammar_digest),
            state_count: tables.fetch(:state_count),
            production_count: tables.fetch(:production_count)
          )
        end

        # @rbs (Blender blender) -> void
        def report_blender_fallback(blender)
          return unless blender.fallback_reason

          @parser.__send__(
            :emit_incremental_event,
            :cst_fallback,
            {
              "reason" => blender.fallback_reason.to_s,
              "limit" => @resource_limits.max_incremental_decomposed_nodes,
              "observed" => blender.decomposed_nodes
            }
          )
        end

        # @rbs (TokenMemo previous_memo, Array[TextEdit] edits, Symbol reason) -> SyntaxResult
        def finish_full_fallback(previous_memo, edits, reason)
          fresh_result, fresh_memo, fresh_parse_memo = parse_current(0.0)
          @last_relex_result = Relexer.reconcile(previous_memo, fresh_memo, edits)
          @last_blender = nil
          @token_memo = fresh_memo
          @parse_memo = fresh_parse_memo
          @result = fresh_result
          @parser.__send__(
            :emit_incremental_event,
            :cst_fallback,
            { "reason" => reason.to_s, "limit" => 0, "observed" => 0 }
          )
          enforce_memo_budget!
          @result
        end

        # @rbs () -> void
        def enforce_memo_budget!
          observed = @token_memo.estimated_bytes + @parse_memo.estimated_bytes
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
