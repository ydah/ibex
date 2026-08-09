# frozen_string_literal: true
# rbs_inline: enabled

require_relative "event_sanitizer" unless defined?(Ibex::Runtime::EventSanitizer)

module Ibex
  module Runtime
    # Syntax-session additions to the frozen Parser signature surface.
    # @rbs!
    #   class Parser
    #     def self.syntax_execution_profile: () -> Symbol
    #
    #     def self.syntax_session: (String | CST::SourceText source, ?execution_profile: Symbol?,
    #       ?resource_limits: ResourceLimits?, ?limits: SyntaxSessionLimits?,
    #       ?cancellation: CancellationToken?, ?blender: bool) -> SyntaxSession
    #   end

    # Raised when a caller has not acknowledged the generated artifact's
    # execution profile.
    class SyntaxSessionTrustError < ArgumentError; end

    # Raised cooperatively at syntax-session operation boundaries and parser
    # observation checkpoints after cancellation is requested.
    class SyntaxSessionCancelled < StandardError; end

    # Raised when a syntax-service-specific resource bound is exceeded.
    class SyntaxSessionResourceLimitError < StandardError
      attr_reader :resource #: Symbol
      attr_reader :limit #: Integer
      attr_reader :observed #: Integer

      # @rbs (resource: Symbol, limit: Integer, observed: Integer) -> void
      def initialize(resource:, limit:, observed:)
        @resource = resource
        @limit = limit
        @observed = observed
        super("syntax session resource limit exceeded: #{resource} is #{observed}, configured maximum is #{limit}")
      end
    end

    # Thread-safe cooperative cancellation state for one or more operations.
    class CancellationToken
      # @rbs () -> void
      def initialize
        @mutex = Mutex.new #: Mutex
        @cancelled = false #: bool
      end

      # @rbs () -> true
      # rubocop:disable Naming/PredicateMethod -- command mutation convention.
      def cancel!
        @mutex.synchronize { @cancelled = true }
        true
      end
      # rubocop:enable Naming/PredicateMethod

      # @rbs () -> bool
      def cancelled?
        @mutex.synchronize { @cancelled }
      end
    end

    # Immutable syntax-service bounds layered over parser ResourceLimits.
    class SyntaxSessionLimits
      DEFAULT_MAX_SOURCE_BYTES = 16 * 1024 * 1024 #: Integer
      DEFAULT_MAX_EDITS_PER_OPERATION = 1_024 #: Integer
      DEFAULT_MAX_INSERTED_BYTES = 4 * 1024 * 1024 #: Integer

      attr_reader :max_source_bytes #: Integer
      attr_reader :max_edits_per_operation #: Integer
      attr_reader :max_inserted_bytes #: Integer

      # @rbs (?max_source_bytes: Integer, ?max_edits_per_operation: Integer,
      #   ?max_inserted_bytes: Integer) -> void
      def initialize(
        max_source_bytes: DEFAULT_MAX_SOURCE_BYTES,
        max_edits_per_operation: DEFAULT_MAX_EDITS_PER_OPERATION,
        max_inserted_bytes: DEFAULT_MAX_INSERTED_BYTES
      )
        validate_positive_integer(max_source_bytes, :max_source_bytes)
        validate_positive_integer(max_edits_per_operation, :max_edits_per_operation)
        validate_nonnegative_integer(max_inserted_bytes, :max_inserted_bytes)
        @max_source_bytes = max_source_bytes
        @max_edits_per_operation = max_edits_per_operation
        @max_inserted_bytes = max_inserted_bytes
        freeze
      end

      private

      # @rbs (Object? value, Symbol name) -> void
      def validate_positive_integer(value, name)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer"
      end

      # @rbs (Object? value, Symbol name) -> void
      def validate_nonnegative_integer(value, name)
        return if value.is_a?(Integer) && value >= 0

        raise ArgumentError, "#{name} must be a nonnegative Integer"
      end
    end

    # Immutable evidence from one completed syntax-session operation.
    class SyntaxSessionMetrics
      attr_reader :reused_ratio #: Float
      attr_reader :reused_tokens #: Integer
      attr_reader :token_count #: Integer
      attr_reader :fallback_reasons #: Array[Symbol]

      # @rbs (reused_ratio: Float, reused_tokens: Integer, token_count: Integer,
      #   fallback_reasons: Array[Symbol]) -> void
      def initialize(reused_ratio:, reused_tokens:, token_count:, fallback_reasons:)
        unless reused_ratio.is_a?(Float) && reused_ratio.finite? && reused_ratio.between?(0.0, 1.0)
          raise ArgumentError, "reused_ratio must be a finite Float in 0.0..1.0"
        end
        unless reused_tokens.is_a?(Integer) && reused_tokens >= 0
          raise ArgumentError, "reused_tokens must be a nonnegative Integer"
        end
        unless token_count.is_a?(Integer) && token_count >= 0
          raise ArgumentError, "token_count must be a nonnegative Integer"
        end
        unless fallback_reasons.is_a?(Array) && fallback_reasons.all?(Symbol)
          raise ArgumentError, "fallback_reasons must contain only Symbols"
        end

        @reused_ratio = reused_ratio
        @reused_tokens = reused_tokens
        @token_count = token_count
        @fallback_reasons = fallback_reasons.dup.freeze
        freeze
      end

      # @rbs () -> bool
      def fallback?
        !@fallback_reasons.empty?
      end
    end

    # Immutable, data-only copy of one parser diagnostic. Application-owned
    # values and locations are sanitized rather than retained by identity.
    class SyntaxSessionDiagnostic
      attr_reader :kind #: Symbol
      attr_reader :data #: Hash[String, EventSanitizer::json_value]

      # @rbs (kind: Symbol, data: Hash[Object?, Object?]) -> void
      def initialize(kind:, data:)
        raise ArgumentError, "diagnostic kind must be a Symbol" unless kind.is_a?(Symbol)
        raise ArgumentError, "diagnostic data must be a Hash" unless data.is_a?(Hash)

        @kind = kind
        @data = EventSanitizer.data(data)
        freeze
      end

      # @rbs () -> Hash[String, EventSanitizer::json_value]
      def to_h
        @data
      end
    end

    # Immutable public snapshot of one completed syntax-session operation.
    class SyntaxSessionResult
      attr_reader :revision #: Integer
      attr_reader :syntax_root #: CST::SyntaxNode
      attr_reader :diagnostics #: Array[SyntaxSessionDiagnostic]
      attr_reader :expected_tokens #: Array[String]
      attr_reader :metrics #: SyntaxSessionMetrics
      attr_reader :status #: Symbol

      # @rbs (revision: Integer, syntax_root: CST::SyntaxNode, diagnostics: Array[SyntaxSessionDiagnostic],
      #   expected_tokens: Array[String], metrics: SyntaxSessionMetrics, status: Symbol) -> void
      def initialize(revision:, syntax_root:, diagnostics:, expected_tokens:, metrics:, status:)
        raise ArgumentError, "revision must be a nonnegative Integer" unless revision.is_a?(Integer) && revision >= 0
        unless diagnostics.is_a?(Array) && diagnostics.all?(SyntaxSessionDiagnostic)
          raise ArgumentError, "diagnostics must contain only SyntaxSessionDiagnostic values"
        end
        unless expected_tokens.is_a?(Array) && expected_tokens.all?(String)
          raise ArgumentError, "expected_tokens must contain only Strings"
        end
        unless metrics.is_a?(SyntaxSessionMetrics)
          raise ArgumentError, "metrics must be an Ibex::Runtime::SyntaxSessionMetrics"
        end
        raise ArgumentError, "status must be :ok or :syntax_error" unless %i[ok syntax_error].include?(status)

        @revision = revision
        @syntax_root = syntax_root
        @diagnostics = diagnostics.dup.freeze
        @expected_tokens = expected_tokens.map { |token| token.dup.freeze }.freeze
        @metrics = metrics
        @status = status
        freeze
      end

      # @rbs () -> bool
      def success?
        @status == :ok
      end
    end

    # Generated-language syntax boundary backed by the existing Red/Green CST
    # incremental engine. It does not execute parser production actions.
    class SyntaxSession
      TRUSTED_PROFILE = :trusted_application_code #: Symbol

      attr_reader :execution_profile #: Symbol
      attr_reader :limits #: SyntaxSessionLimits

      # @rbs (Class parser_class, String | CST::SourceText source,
      #   execution_profile: Symbol?, ?resource_limits: ResourceLimits?,
      #   ?limits: SyntaxSessionLimits?, ?cancellation: CancellationToken?, ?blender: bool) -> void
      def initialize(
        parser_class,
        source,
        execution_profile:,
        resource_limits: nil,
        limits: nil,
        cancellation: nil,
        blender: true
      )
        @execution_profile = validate_execution_profile(parser_class, execution_profile)
        @limits = limits || SyntaxSessionLimits.new #: SyntaxSessionLimits
        unless @limits.is_a?(SyntaxSessionLimits)
          raise ArgumentError, "limits must be an Ibex::Runtime::SyntaxSessionLimits"
        end
        unless cancellation.nil? || cancellation.is_a?(CancellationToken)
          raise ArgumentError, "cancellation must be an Ibex::Runtime::CancellationToken or nil"
        end

        @cancellation = cancellation #: CancellationToken?
        @parser_class = parser_class #: Class
        @resource_limits = resource_limits || ResourceLimits.new #: ResourceLimits
        @mutex = Mutex.new #: Mutex
        @revision = 0 #: Integer
        @operation_expected_tokens = [] #: Array[String]
        @operation_fallback_reasons = [] #: Array[Symbol]

        source_text = normalize_source(source)
        enforce_limit!(:source_bytes, @limits.max_source_bytes, source_text.bytesize)
        cancellation_checkpoint!
        event_observer = ->(event, parser) { handle_runtime_event(event, parser) } #: Proc
        @incremental = CST::IncrementalParseSession.new(
          parser_class,
          source_text,
          resource_limits: @resource_limits,
          blender: blender,
          event_observer: event_observer
        ) #: CST::IncrementalParseSession
        @result = snapshot(@incremental.result) #: SyntaxSessionResult
      rescue ResourceLimitError => e
        raise SyntaxSessionResourceLimitError.new(resource: e.resource, limit: e.limit, observed: e.observed), cause: e
      end

      # @rbs () -> CST::SourceText
      def source_text
        @mutex.synchronize { @incremental.source_text }
      end

      # @rbs () -> SyntaxSessionResult
      def result
        @mutex.synchronize { @result }
      end

      # Apply byte-oriented edits against the current source.
      # @rbs (Array[CST::TextEdit] edits) -> SyntaxSessionResult
      def apply_edits(edits)
        @mutex.synchronize { apply_edits_locked(edits) }
      end

      # Propose byte edits through the existing bounded repair search, then
      # validate them with a fresh syntax-only parse. The session is unchanged.
      # @rbs (?policy: RepairPolicy, ?token_text: Hash[String, String]) -> SyntaxRepairResult
      def repair(policy: RepairPolicy.new, token_text: {})
        @mutex.synchronize do
          SyntaxRepairer.new(
            @parser_class, @incremental.source_text, @result,
            execution_profile: @execution_profile, resource_limits: @resource_limits,
            limits: @limits, cancellation: @cancellation, policy: policy, token_text: token_text
          ).call
        end
      end

      private

      # @rbs (Array[CST::TextEdit] edits) -> SyntaxSessionResult
      def apply_edits_locked(edits)
        raise ArgumentError, "edits must be an Array" unless edits.is_a?(Array)

        cancellation_checkpoint!
        enforce_limit!(:edits_per_operation, @limits.max_edits_per_operation, edits.length)
        normalized = CST::TextEdit.normalize(edits)
        inserted_bytes = normalized.sum { |edit| edit.insert_text.bytesize }
        enforce_limit!(:inserted_bytes, @limits.max_inserted_bytes, inserted_bytes)
        next_source = @incremental.source_text.apply(normalized)
        enforce_limit!(:source_bytes, @limits.max_source_bytes, next_source.bytesize)
        return @result if normalized.empty?

        reset_operation_evidence
        parsed = @incremental.edit(normalized)
        @revision += 1
        @result = snapshot(parsed)
      rescue ResourceLimitError => e
        raise SyntaxSessionResourceLimitError.new(resource: e.resource, limit: e.limit, observed: e.observed), cause: e
      end

      # @rbs (Class parser_class, Symbol? acknowledged) -> Symbol
      def validate_execution_profile(parser_class, acknowledged)
        unless parser_class.is_a?(Class) && parser_class <= Parser
          raise ArgumentError, "parser_class must inherit from Ibex::Runtime::Parser"
        end

        profile = parser_class.syntax_execution_profile
        unless profile == TRUSTED_PROFILE
          raise SyntaxSessionTrustError,
                "declarative syntax artifacts are not available; generated parser profile was #{profile.inspect}"
        end
        return profile if acknowledged == profile

        raise SyntaxSessionTrustError,
              "syntax_session executes generated lexer actions; " \
              "pass execution_profile: #{profile.inspect} to acknowledge it"
      end

      # @rbs (String | CST::SourceText source) -> CST::SourceText
      def normalize_source(source)
        return source if source.is_a?(CST::SourceText)
        raise ArgumentError, "source must be a String or Ibex::Runtime::CST::SourceText" unless source.is_a?(String)
        unless source.encoding.ascii_compatible?
          raise Encoding::CompatibilityError, "syntax session source must use an ASCII-compatible encoding"
        end

        CST::SourceText.new(source)
      end

      # @rbs (Symbol resource, Integer limit, Integer observed) -> void
      def enforce_limit!(resource, limit, observed)
        return unless observed > limit

        raise SyntaxSessionResourceLimitError.new(resource: resource, limit: limit, observed: observed)
      end

      # @rbs () -> void
      def cancellation_checkpoint!
        return unless @cancellation&.cancelled?

        raise SyntaxSessionCancelled, "syntax session operation was cancelled"
      end

      # @rbs (Event event, Parser parser) -> void
      def handle_runtime_event(event, parser)
        cancellation_checkpoint!
        case event.type
        when :error
          parser.expected_tokens.each do |token|
            @operation_expected_tokens << token unless @operation_expected_tokens.include?(token)
          end
        when :cst_fallback
          @operation_fallback_reasons << event.data.fetch("reason").to_sym
        end
      end

      # @rbs () -> void
      def reset_operation_evidence
        @operation_expected_tokens = [] #: Array[String]
        @operation_fallback_reasons = [] #: Array[Symbol]
      end

      # @rbs (CST::SyntaxResult parsed) -> SyntaxSessionResult
      def snapshot(parsed)
        token_count = @incremental.token_memo.tokens.length
        reused_tokens = if @incremental.last_full_fallback?
                          0
                        else
                          @incremental.last_relex_result&.reused_count.to_i
                        end
        metrics = SyntaxSessionMetrics.new(
          reused_ratio: parsed.reused_ratio,
          reused_tokens: reused_tokens,
          token_count: token_count,
          fallback_reasons: @operation_fallback_reasons
        )
        SyntaxSessionResult.new(
          revision: @revision,
          syntax_root: parsed.syntax_root,
          diagnostics: immutable_diagnostics(parsed.diagnostics),
          expected_tokens: @operation_expected_tokens,
          metrics: metrics,
          status: parsed.diagnostics.empty? ? :ok : :syntax_error
        )
      end

      # @rbs (Array[Object?] diagnostics) -> Array[SyntaxSessionDiagnostic]
      def immutable_diagnostics(diagnostics)
        diagnostics.map do |diagnostic|
          if diagnostic.is_a?(ParseError)
            SyntaxSessionDiagnostic.new(
              kind: :parse_error,
              data: {
                message: diagnostic.message,
                token_id: diagnostic.token_id,
                token_name: diagnostic.token_name,
                expected_tokens: diagnostic.expected_tokens,
                location: EventSanitizer.location(diagnostic.location)
              }
            )
          else
            SyntaxSessionDiagnostic.new(kind: :syntax_error, data: diagnostic)
          end
        end.freeze
      end
    end
  end
end
