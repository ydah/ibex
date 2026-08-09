# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # @rbs!
    #   type syntax_edit_document = {
    #     kind: Symbol,
    #     position: Integer,
    #     token_id: Integer,
    #     token_name: String,
    #     cost: Integer,
    #     start_byte: Integer,
    #     end_byte: Integer,
    #     original_text: String,
    #     replacement_text: String?
    #   }

    # One syntax-only projection of a runtime repair edit. It intentionally
    # carries source bytes and token identity, never an application value.
    class SyntaxRepairEdit
      attr_reader :kind #: Symbol
      attr_reader :position #: Integer
      attr_reader :token_id #: Integer
      attr_reader :token_name #: String
      attr_reader :cost #: Integer
      attr_reader :start_byte #: Integer
      attr_reader :end_byte #: Integer
      attr_reader :original_text #: String
      attr_reader :replacement_text #: String?

      # @rbs (kind: Symbol, position: Integer, token_id: Integer, token_name: String, cost: Integer,
      #   start_byte: Integer, end_byte: Integer, original_text: String, replacement_text: String?) -> void
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def initialize(kind:, position:, token_id:, token_name:, cost:, start_byte:, end_byte:, original_text:,
                     replacement_text:)
        raise ArgumentError, "unknown syntax repair edit #{kind.inspect}" unless RepairEdit::KINDS.include?(kind)
        unless position.is_a?(Integer) && position >= 0
          raise ArgumentError, "syntax repair edit position must be nonnegative"
        end
        unless token_id.is_a?(Integer) && token_id >= 0
          raise ArgumentError, "syntax repair token id must be nonnegative"
        end
        unless token_name.is_a?(String) && !token_name.empty?
          raise ArgumentError, "syntax repair token name must be a nonempty String"
        end
        raise ArgumentError, "syntax repair edit cost must be positive" unless cost.is_a?(Integer) && cost.positive?
        unless start_byte.is_a?(Integer) && end_byte.is_a?(Integer) && start_byte >= 0 && end_byte >= start_byte
          raise ArgumentError, "syntax repair byte range is invalid"
        end
        unless original_text.is_a?(String) && (replacement_text.nil? || replacement_text.is_a?(String))
          raise ArgumentError, "syntax repair edit text must be String values"
        end
        if kind == :insert && (start_byte != end_byte || !original_text.empty?)
          raise ArgumentError, "syntax insertion must have an empty source range"
        end
        if kind == :delete && replacement_text != ""
          raise ArgumentError, "syntax deletion must have an empty replacement"
        end
        unless original_text.bytesize == end_byte - start_byte
          raise ArgumentError, "syntax repair original text does not match its byte range"
        end

        @kind = kind
        @position = position
        @token_id = token_id
        @token_name = token_name.dup.freeze
        @cost = cost
        @start_byte = start_byte
        @end_byte = end_byte
        @original_text = original_text.b.freeze
        @replacement_text = replacement_text&.b&.freeze
        freeze
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # @rbs () -> syntax_edit_document
      def to_h
        value = {
          kind: @kind, position: @position, token_id: @token_id, token_name: @token_name, cost: @cost,
          start_byte: @start_byte, end_byte: @end_byte, original_text: @original_text,
          replacement_text: @replacement_text
        } # @type var value: syntax_edit_document
        value.freeze
      end
    end

    # One selected runtime plan plus its source-oriented edit projection.
    class SyntaxRepairPlan
      attr_reader :runtime_plan #: RepairPlan
      attr_reader :edits #: Array[SyntaxRepairEdit]
      attr_reader :cost #: Integer
      attr_reader :configurations #: Integer

      # @rbs (runtime_plan: RepairPlan, edits: Array[SyntaxRepairEdit]) -> void
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def initialize(runtime_plan:, edits:)
        unless runtime_plan.is_a?(RepairPlan) && edits.is_a?(Array) && edits.all?(SyntaxRepairEdit)
          raise ArgumentError, "syntax repair plan requires one runtime plan and syntax edits"
        end
        raise ArgumentError, "syntax repair edit count must match the runtime plan" unless
          runtime_plan.edits.length == edits.length

        runtime_plan.edits.each_with_index do |runtime_edit, index|
          syntax_edit = edits.fetch(index)
          next if runtime_edit.kind == syntax_edit.kind && runtime_edit.position == syntax_edit.position &&
                  runtime_edit.token_id == syntax_edit.token_id && runtime_edit.token_name == syntax_edit.token_name &&
                  runtime_edit.cost == syntax_edit.cost

          raise ArgumentError, "syntax repair edit metadata must match its runtime plan"
        end

        @runtime_plan = runtime_plan
        @edits = edits.dup.freeze
        @cost = runtime_plan.cost
        @configurations = runtime_plan.configurations
        freeze
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end

    # Immutable syntax-only repair attempt. There is deliberately no `value`.
    class SyntaxRepairResult
      STATUSES = %i[accepted progress rejected unavailable exhausted not_found].freeze #: Array[Symbol]
      BOUNDED_STATUSES = %i[selected exhausted not_found].freeze #: Array[Symbol]

      attr_reader :status #: Symbol
      attr_reader :bounded_status #: Symbol
      attr_reader :reason #: Symbol?
      attr_reader :plan #: SyntaxRepairPlan?
      attr_reader :text_edits #: Array[CST::TextEdit]
      attr_reader :syntax_root #: CST::SyntaxNode
      attr_reader :diagnostics #: Array[SyntaxSessionDiagnostic]
      attr_reader :updated_source #: CST::SourceText?
      attr_reader :validation #: SyntaxSessionResult?

      # @rbs (status: Symbol, bounded_status: Symbol, reason: Symbol?, plan: SyntaxRepairPlan?,
      #   text_edits: Array[CST::TextEdit], syntax_root: CST::SyntaxNode,
      #   diagnostics: Array[SyntaxSessionDiagnostic], updated_source: CST::SourceText?,
      #   validation: SyntaxSessionResult?) -> void
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def initialize(status:, bounded_status:, reason:, plan:, text_edits:, syntax_root:, diagnostics:,
                     updated_source:, validation:)
        raise ArgumentError, "unknown syntax repair status #{status.inspect}" unless STATUSES.include?(status)
        unless BOUNDED_STATUSES.include?(bounded_status)
          raise ArgumentError, "unknown syntax repair bounded status #{bounded_status.inspect}"
        end
        unless text_edits.is_a?(Array) && text_edits.all?(CST::TextEdit)
          raise ArgumentError, "syntax repair text_edits must contain only CST::TextEdit values"
        end
        unless diagnostics.is_a?(Array) && diagnostics.all?(SyntaxSessionDiagnostic)
          raise ArgumentError, "syntax repair diagnostics must be immutable syntax-session diagnostics"
        end
        raise ArgumentError, "syntax_root must be a CST::SyntaxNode" unless syntax_root.is_a?(CST::SyntaxNode)
        raise ArgumentError, "syntax repair reason must be a Symbol or nil" unless reason.nil? || reason.is_a?(Symbol)
        unless plan.nil? || plan.is_a?(SyntaxRepairPlan)
          raise ArgumentError, "syntax repair plan must be a SyntaxRepairPlan or nil"
        end
        unless updated_source.nil? || updated_source.is_a?(CST::SourceText)
          raise ArgumentError, "updated_source must be a CST::SourceText or nil"
        end
        unless validation.nil? || validation.is_a?(SyntaxSessionResult)
          raise ArgumentError, "validation must be a SyntaxSessionResult or nil"
        end

        validate_result_shape!(status, bounded_status, reason, plan, text_edits, updated_source, validation)

        @status = status
        @bounded_status = bounded_status
        @reason = reason
        @plan = plan
        @text_edits = text_edits.dup.freeze
        @syntax_root = syntax_root
        @diagnostics = diagnostics.dup.freeze
        @updated_source = updated_source
        @validation = validation
        freeze
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # @rbs () -> bool
      def accepted? = @status == :accepted

      # @rbs () -> bool
      def progress? = %i[accepted progress].include?(@status)

      private

      # @rbs (Symbol, Symbol, Symbol?, SyntaxRepairPlan?, Array[CST::TextEdit], CST::SourceText?,
      #   SyntaxSessionResult?) -> void
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def validate_result_shape!(status, bounded_status, reason, plan, text_edits, updated_source, validation)
        if %i[accepted progress rejected].include?(status)
          raise ArgumentError, "a completed syntax repair must be selected" unless bounded_status == :selected
          raise ArgumentError, "a completed syntax repair requires a plan" unless plan
          raise ArgumentError, "a completed syntax repair requires text edits" if text_edits.empty?
          raise ArgumentError, "a completed syntax repair requires updated source and validation" unless
            updated_source && validation
          raise ArgumentError, "a completed syntax repair cannot have a reason" unless reason.nil?
          raise ArgumentError, "accepted validation must succeed" if status == :accepted && !validation.success?
          if %i[progress rejected].include?(status) && validation.success?
            raise ArgumentError, "non-accepted validation must report an error"
          end

          return
        end

        if status == :unavailable
          raise ArgumentError, "unavailable syntax repair must be selected" unless bounded_status == :selected
          raise ArgumentError, "unavailable syntax repair requires a reason" unless reason
        elsif status != bounded_status || !%i[exhausted not_found].include?(status)
          raise ArgumentError, "bounded status does not match syntax repair status"
        end
        raise ArgumentError, "unavailable or bounded syntax repair cannot expose text edits" unless text_edits.empty?
        return unless updated_source || validation

        raise ArgumentError,
              "unavailable or bounded syntax repair cannot expose validation"
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end

    # Executes one fresh syntax-only repair attempt without mutating its source
    # SyntaxSession. Generated lexer actions retain the acknowledged trust
    # profile; parser production actions remain suppressed.
    class SyntaxRepairer
      # @rbs (Class parser_class, CST::SourceText source, SyntaxSessionResult baseline,
      #   execution_profile: Symbol, resource_limits: ResourceLimits, limits: SyntaxSessionLimits,
      #   cancellation: CancellationToken?, policy: RepairPolicy, token_text: Hash[String, String]) -> void
      def initialize(parser_class, source, baseline, execution_profile:, resource_limits:, limits:, cancellation:,
                     policy:, token_text:)
        @parser_class = parser_class
        @source = source
        @baseline = baseline
        @execution_profile = execution_profile
        @resource_limits = resource_limits
        @limits = limits
        @cancellation = cancellation
        @policy = validate_policy(policy)
        @token_text = validate_token_text(token_text)
      end

      # @rbs () -> SyntaxRepairResult
      def call
        cancellation_checkpoint!
        parser = @parser_class.__send__(:new, resource_limits: @resource_limits)
        captures = install_capture(parser)
        parser.repair_policy = @policy
        parser.observe { |_event| cancellation_checkpoint! }
        parsed = parser.__send__(:parse_syntax_with_cache, @source, CST::NodeCache.new)
        cancellation_checkpoint!
        diagnostics = immutable_diagnostics(parsed.diagnostics)
        return unavailable(:repair_source_not_consumed, parsed, diagnostics) unless
          @source.text.start_with?(parsed.syntax_root.to_source)

        outcomes = parser.__send__(:syntax_repair_search_results)
        return bounded_failure(:exhausted, :search_exhausted, parsed, diagnostics) if
          outcomes.any? { |outcome| outcome.status == :exhausted }
        return bounded_failure(:not_found, :no_repair_plan, parsed, diagnostics) if captures.empty?
        return unavailable(:multiple_repair_segments, parsed, diagnostics) unless captures.one?

        build_selected(captures.fetch(0), parsed, diagnostics)
      rescue ResourceLimitError => e
        raise SyntaxSessionResourceLimitError.new(resource: e.resource, limit: e.limit, observed: e.observed), cause: e
      end

      private

      # @rbs (Parser parser) -> Array[[RepairPlan, Array[RepairInput]]]
      def install_capture(parser)
        captures = [] #: Array[[RepairPlan, Array[RepairInput]]]
        parser.define_singleton_method(:on_repair) do |plan|
          inputs = __send__(:syntax_repair_inputs)
          captures << [plan, inputs]
        end
        captures
      end

      # @rbs ([RepairPlan, Array[RepairInput]] capture, CST::SyntaxResult parsed,
      #   Array[SyntaxSessionDiagnostic] diagnostics) -> SyntaxRepairResult
      def build_selected(capture, parsed, diagnostics)
        runtime_plan, inputs = capture
        projected = project_edits(runtime_plan, inputs)
        plan = SyntaxRepairPlan.new(runtime_plan: runtime_plan, edits: projected)
        return unavailable(:missing_token_text, parsed, diagnostics, plan: plan) if
          projected.any? { |edit| %i[insert replace].include?(edit.kind) && edit.replacement_text.nil? }

        text_edits = normalize_text_edits(projected)
        validate_edit_limits!(text_edits)
        updated_source = @source.apply(text_edits)
        enforce_limit!(:source_bytes, @limits.max_source_bytes, updated_source.bytesize)
        cancellation_checkpoint!
        validation = fresh_validation(updated_source)
        cancellation_checkpoint!
        return unavailable(:validation_source_not_consumed, parsed, diagnostics, plan: plan) unless
          updated_source.text.start_with?(validation.syntax_root.to_source)

        status = validation_status(validation, updated_source)
        SyntaxRepairResult.new(
          status: status, bounded_status: :selected, reason: nil, plan: plan, text_edits: text_edits,
          syntax_root: parsed.syntax_root, diagnostics: diagnostics, updated_source: updated_source,
          validation: validation
        )
      rescue ArgumentError => e
        return unavailable(:overlapping_text_edits, parsed, diagnostics, plan: plan) if
          e.message.include?("text edits overlap")

        raise
      end

      # @rbs (RepairPlan plan, Array[RepairInput] inputs) -> Array[SyntaxRepairEdit]
      def project_edits(plan, inputs)
        plan.edits.map do |edit|
          input = inputs.fetch(edit.position)
          start_byte, end_byte = input_range(input)
          replacement = replacement_text(edit)
          end_byte = start_byte if edit.kind == :insert
          SyntaxRepairEdit.new(
            kind: edit.kind, position: edit.position, token_id: edit.token_id,
            token_name: edit.token_name, cost: edit.cost, start_byte: start_byte,
            end_byte: end_byte, original_text: edit.kind == :insert ? "".b : original_text(start_byte, end_byte),
            replacement_text: replacement
          )
        end
      end

      # @rbs (RepairInput input) -> [Integer, Integer]
      def input_range(input)
        location = input.location
        start_byte = location_value(location, :start_byte)
        end_byte = location_value(location, :end_byte)
        unless start_byte.is_a?(Integer) && end_byte.is_a?(Integer)
          raise ArgumentError, "syntax repair requires byte-oriented generated lexer locations"
        end

        [start_byte, end_byte]
      end

      # @rbs (RepairEdit edit) -> String?
      def replacement_text(edit)
        return "".b if edit.kind == :delete

        explicit = @token_text[edit.token_name]
        return explicit if explicit

        punctuation_literal(edit.token_name)
      end

      # @rbs (String name) -> String?
      def punctuation_literal(name)
        inner = if name.length >= 2 && ["'", '"'].include?(name[0]) && name[-1] == name[0]
                  name[1...-1]
                else
                  name
                end
        return unless inner && !inner.empty? && inner.match?(/\A[[:punct:]]+\z/)

        inner.b.freeze
      end

      # @rbs (Integer start_byte, Integer end_byte) -> String
      def original_text(start_byte, end_byte)
        (@source.text.byteslice(start_byte, end_byte - start_byte) || "".b).freeze
      end

      # @rbs (Array[SyntaxRepairEdit] edits) -> Array[CST::TextEdit]
      def normalize_text_edits(edits)
        CST::TextEdit.normalize(edits.map do |edit|
          insert_text = edit.replacement_text || raise(ArgumentError, "missing token text")
          delete_length = edit.kind == :insert ? 0 : edit.end_byte - edit.start_byte
          CST::TextEdit.new(start: edit.start_byte, delete_length: delete_length, insert_text: insert_text)
        end)
      end

      # @rbs (Array[CST::TextEdit] edits) -> void
      def validate_edit_limits!(edits)
        enforce_limit!(:edits_per_operation, @limits.max_edits_per_operation, edits.length)
        inserted = edits.sum { |edit| edit.insert_text.bytesize }
        enforce_limit!(:inserted_bytes, @limits.max_inserted_bytes, inserted)
      end

      # @rbs (CST::SourceText source) -> SyntaxSessionResult
      def fresh_validation(source)
        SyntaxSession.new(
          @parser_class, source, execution_profile: @execution_profile,
                                 resource_limits: @resource_limits, limits: @limits,
                                 cancellation: @cancellation, blender: false
        ).result
      end

      # @rbs (SyntaxSessionResult validation, CST::SourceText source) -> Symbol
      def validation_status(validation, source)
        return :accepted if validation.success? && validation.syntax_root.to_source == source.text

        baseline_count = @baseline.diagnostics.length
        current_count = validation.diagnostics.length
        return :progress if current_count < baseline_count

        before = first_diagnostic_byte(@baseline)
        after = first_diagnostic_byte(validation)
        after.is_a?(Integer) && before.is_a?(Integer) && after > before ? :progress : :rejected
      end

      # @rbs (SyntaxSessionResult result) -> Integer?
      def first_diagnostic_byte(result)
        value = result.diagnostics.first&.data&.dig("location", "start_byte")
        value if value.is_a?(Integer)
      end

      # @rbs (Symbol status, Symbol reason, CST::SyntaxResult parsed,
      #   Array[SyntaxSessionDiagnostic] diagnostics) -> SyntaxRepairResult
      def bounded_failure(status, reason, parsed, diagnostics)
        SyntaxRepairResult.new(
          status: status, bounded_status: status, reason: reason, plan: nil, text_edits: [],
          syntax_root: parsed.syntax_root, diagnostics: diagnostics, updated_source: nil, validation: nil
        )
      end

      # @rbs (Symbol reason, CST::SyntaxResult parsed, Array[SyntaxSessionDiagnostic] diagnostics,
      #   ?plan: SyntaxRepairPlan?) -> SyntaxRepairResult
      def unavailable(reason, parsed, diagnostics, plan: nil)
        SyntaxRepairResult.new(
          status: :unavailable, bounded_status: :selected, reason: reason, plan: plan, text_edits: [],
          syntax_root: parsed.syntax_root, diagnostics: diagnostics, updated_source: nil, validation: nil
        )
      end

      # @rbs (Array[Object] diagnostics) -> Array[SyntaxSessionDiagnostic]
      def immutable_diagnostics(diagnostics)
        diagnostics.map do |diagnostic|
          if diagnostic.is_a?(ParseError)
            SyntaxSessionDiagnostic.new(
              kind: :parse_error,
              data: {
                message: diagnostic.message, token_id: diagnostic.token_id, token_name: diagnostic.token_name,
                expected_tokens: diagnostic.expected_tokens, location: EventSanitizer.location(diagnostic.location)
              }
            )
          else
            data = diagnostic #: Hash[Object?, Object?]
            SyntaxSessionDiagnostic.new(kind: :syntax_error, data: data)
          end
        end.freeze
      end

      # @rbs (Object location, Symbol key) -> Object?
      def location_value(location, key)
        return location.public_send(key) if location.respond_to?(key)

        if location.is_a?(Hash)
          hash = location #: Hash[Object, Object]
          return hash[key] || hash[key.to_s]
        end

        nil
      end

      # @rbs (RepairPolicy policy) -> RepairPolicy
      def validate_policy(policy)
        return policy if policy.is_a?(RepairPolicy)

        raise ArgumentError, "policy must be an Ibex::Runtime::RepairPolicy"
      end

      # @rbs (Hash[String, String] value) -> Hash[String, String]
      def validate_token_text(value)
        unless value.is_a?(Hash) && value.all? { |name, text| name.is_a?(String) && text.is_a?(String) && !text.empty? }
          raise ArgumentError, "token_text must map String token names to nonempty String source bytes"
        end

        value.to_h { |name, text| [name.dup.freeze, text.b.freeze] }.freeze
      end

      # @rbs (Symbol resource, Integer limit, Integer observed) -> void
      def enforce_limit!(resource, limit, observed)
        return unless observed > limit

        raise SyntaxSessionResourceLimitError.new(resource: resource, limit: limit, observed: observed)
      end

      # @rbs () -> void
      def cancellation_checkpoint!
        return unless @cancellation&.cancelled?

        raise SyntaxSessionCancelled, "syntax repair operation was cancelled"
      end
    end
  end
end
