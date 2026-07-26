# frozen_string_literal: true
# rbs_inline: enabled

require_relative "location_span" unless defined?(Ibex::Runtime::LocationSpan)
require_relative "observation" unless defined?(Ibex::Runtime::Observation)
require_relative "resource_limits" unless defined?(Ibex::Runtime::ResourceLimits)
require_relative "repair" unless defined?(Ibex::Runtime::RepairPolicy)
require_relative "repair_search" unless defined?(Ibex::Runtime::RepairSearch)
require_relative "parser_sync_recovery" unless defined?(Ibex::Runtime::ParserSyncRecovery)

module Ibex
  module Runtime
    # Current parser-table shape emitted by the generator.
    PARSER_TABLE_FORMAT_VERSION = 3 #: Integer
    # Parser-table shapes this runtime can execute.
    SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS = [1, 2, PARSER_TABLE_FORMAT_VERSION].freeze #: Array[Integer]

    # Raised by the default parser error handler.
    class ParseError < StandardError
      attr_reader :token_id #: Integer?
      attr_reader :token_name #: String?
      attr_reader :token_value #: untyped
      attr_reader :expected_tokens #: Array[String]
      attr_reader :location #: untyped
      attr_reader :state #: Integer?
      attr_reader :suggestions #: Array[String]
      attr_reader :error_id #: String?

      # rubocop:disable Layout/LineLength
      # @rbs (?String? message, ?token_id: Integer?, ?token_name: String?, ?token_value: untyped, ?expected_tokens: Array[String], ?location: untyped, ?state: Integer?, ?suggestions: Array[String], ?error_id: String?, ?detail: String?) -> void
      # rubocop:enable Layout/LineLength
      def initialize(
        message = nil,
        token_id: nil,
        token_name: nil,
        token_value: nil,
        expected_tokens: [],
        location: nil,
        state: nil,
        suggestions: [],
        error_id: nil,
        detail: nil
      )
        @token_id = token_id
        @token_name = token_name
        @token_value = token_value
        @expected_tokens = expected_tokens.dup.freeze
        @location = location
        @state = state
        @suggestions = suggestions.dup.freeze
        @error_id = error_id&.dup&.freeze
        @detail = detail
        super(message || diagnostic_message)
      end

      # @rbs () -> String
      def location_label
        file = location_value(:file) || "(input)"
        line = location_value(:line) || 1
        column = location_value(:column) || 1
        "#{file}:#{line}:#{column}"
      end

      private

      # @rbs () -> String
      def diagnostic_message
        expected = @expected_tokens.empty? ? "" : "; expected #{@expected_tokens.join(', ')}"
        default = "unexpected #{@token_name || @token_id}#{expected} (#{@token_value.inspect})"
        identifier = @error_id ? "[#{@error_id}] " : ""
        message = "#{location_label}: #{identifier}#{@detail || default}"
        source_line = location_value(:source_line)
        column = location_value(:column)
        message += "\n#{source_line}\n#{' ' * [column.to_i - 1, 0].max}^" if source_line
        message += "\ndid you mean #{@suggestions.join(' or ')}?" unless @suggestions.empty?
        message
      end

      # @rbs (Symbol key) -> untyped
      def location_value(key)
        return nil unless @location
        return @location.public_send(key) if @location.respond_to?(key)
        return @location[key] || @location[key.to_s] if @location.is_a?(Hash)

        nil
      end
    end

    # Raised when a configured parser-session resource budget is exhausted.
    class ResourceLimitError < ParseError
      attr_reader :resource #: Symbol
      attr_reader :limit #: Integer
      attr_reader :observed #: Integer

      # @rbs (resource: Symbol, limit: Integer, observed: Integer, state: Integer?, location: untyped) -> void
      def initialize(resource:, limit:, observed:, state:, location:)
        @resource = resource
        @limit = limit
        @observed = observed
        super(
          "parser resource limit exceeded: #{resource} is #{observed}, configured maximum is #{limit}",
          state: state, location: location
        )
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        {
          type: :resource_limit, resource: @resource, limit: @limit, observed: @observed,
          state: state, location: location
        }.freeze
      end
    end

    # rubocop:disable Metrics/ClassLength

    # Drives a table-defined LR parser without native extensions.
    #
    # Subclasses provide `.parser_tables`, returning `:tokens`, `:token_names`,
    # `:actions`, `:gotos`, and `:productions`, with optional
    # `:default_actions`, `:error_messages`, and `:recovery_sync_tokens`.
    # Actions are represented by
    # `[:shift, state]`, `[:reduce, production]`, `[:accept]`, or `[:error]`.
    # Format-v2 and v3 generated production entries mark their five-argument
    # semantic methods with `location_action: true`. Format-v3 composed actions
    # additionally use `composition_action: true` for the six-argument contract
    # carrying the lookahead location. V1 and unmarked application actions
    # retain the historical two-argument contract. Markers are honored only for
    # the generated `_ibex_action_N` Symbol shape, never for callables.
    class Parser
      include Observation
      include ParserSyncRecovery

      ParseError = Ibex::Runtime::ParseError #: singleton(Ibex::Runtime::ParseError)
      EOF_TOKEN = 0 #: Integer
      ERROR_TOKEN = 1 #: Integer
      GENERATED_ACTION_NAME = /\A_ibex_action_\d+\z/ #: Regexp
      NO_LOOKAHEAD = Object.new.freeze #: Object
      RECOVERY_SHIFTS = 3 #: Integer
      ERROR_ACTION = [:error].freeze #: [:error]
      SYNC_RECOVER_ACTION = [:sync_recover].freeze #: [:sync_recover]
      CONTINUE_OUTCOME = [:continue].freeze #: [:continue]
      REPAIR_PENDING_OUTCOME = [:repair_pending].freeze #: [:repair_pending]
      empty_row = {} # @type var empty_row: Hash[Integer, untyped]
      empty_location_names = {} # @type var empty_location_names: Hash[Symbol, Integer]

      EMPTY_ROW = empty_row.freeze #: Hash[Integer, untyped]
      EMPTY_LOCATION_NAMES = empty_location_names.freeze #: Hash[Symbol, Integer]
      private_constant :ERROR_ACTION, :SYNC_RECOVER_ACTION, :CONTINUE_OUTCOME, :REPAIR_PENDING_OUTCOME

      # @rbs @yydebug: bool
      # @rbs @yydebug_output: IO
      # @rbs @source: (^() -> untyped)?
      # @rbs @state_stack: Array[Integer]
      # @rbs @value_stack: Array[untyped]
      # @rbs @vstack: Array[untyped]
      # @rbs @racc_vstack: Array[untyped]
      # @rbs @location_stack: Array[untyped]?
      # @rbs @lookahead: untyped
      # @rbs @lookahead_value: untyped
      # @rbs @lookahead_location: untyped
      # @rbs @recovery_shifts: Integer
      # @rbs @semantic_error: bool
      # @rbs @accept_requested: bool
      # @rbs @unknown_token_id: Integer?
      # @rbs @unknown_token_name: String?
      # @rbs @push_status: :idle | :active | :finished
      # @rbs @driver_status: :idle | :pull | :push
      # @rbs @runtime_driver_thread: Thread?
      # @rbs @runtime_observers: Hash[Observation::Subscription, Proc]?
      # @rbs @runtime_event_sequence: Integer
      # @rbs @runtime_lookahead_token_display: untyped
      # @rbs @runtime_observation_mutex: Mutex
      # @rbs @repair_policy: RepairPolicy?
      # @rbs @repair_input_buffer: Array[RepairInput]?
      # @rbs @repair_selected: bool
      # @rbs @semantic_locations: Array[untyped]?
      # @rbs @semantic_location_names: Hash[Symbol, Integer]?
      # @rbs @semantic_result_location: untyped
      # @rbs @trace_value_printer: (^(untyped) -> untyped)?
      # @rbs @sync_recovery_context: Hash[Symbol, untyped]?
      # @rbs @sync_recovery_token_data: Hash[String, untyped]?
      # @rbs @sync_recovery_observers: Array[Proc]?
      # @rbs @cst_errors: Array[CST::Error]
      # @rbs @resource_limits: ResourceLimits
      # @rbs @recovery_attempts: Integer

      # @rbs (?resource_limits: ResourceLimits) -> void
      def initialize(resource_limits: ResourceLimits.new)
        validate_resource_limits!(resource_limits)
        initialize_runtime_state(resource_limits, preserve_existing: false)
      end

      # @rbs () -> bool
      def yydebug
        ensure_runtime_initialized!
        @yydebug
      end

      # @rbs (bool enabled) -> bool
      def yydebug=(enabled)
        ensure_runtime_initialized!
        @yydebug = enabled
      end

      # @rbs (IO output) -> IO
      def yydebug_output=(output)
        ensure_runtime_initialized!
        @yydebug_output = output
      end

      # @rbs () -> RepairPolicy?
      def repair_policy
        ensure_runtime_initialized!
        @repair_policy
      end

      # @rbs () -> ResourceLimits
      def resource_limits
        ensure_runtime_initialized!
        @resource_limits
      end

      # Enable bounded automatic repair for the next parser session.
      # Assign nil to restore the compatible yacc-only behavior.
      # @rbs (RepairPolicy? policy) -> RepairPolicy?
      def repair_policy=(policy)
        ensure_runtime_initialized!
        unless policy.nil? || policy.is_a?(RepairPolicy)
          raise ArgumentError, "repair_policy must be an Ibex::Runtime::RepairPolicy or nil"
        end

        @runtime_observation_mutex.synchronize do
          ensure_driver_available_without_lock!
          if @push_status == :active
            raise ParseError, "(repair):1:1: repair_policy cannot change during an active push session"
          end

          @repair_policy = policy
        end
      end

      # Replace the limits used by future sessions.
      # @rbs (ResourceLimits limits) -> ResourceLimits
      def resource_limits=(limits)
        ensure_runtime_initialized!
        validate_resource_limits!(limits)

        @runtime_observation_mutex.synchronize do
          ensure_driver_available_without_lock!
          if @push_status == :active
            raise ParseError, "(resource):1:1: resource_limits cannot change during an active push session"
          end

          @resource_limits = limits
        end
      end

      # Pull tokens from `next_token` and parse them.
      # @rbs () -> untyped
      def do_parse
        drive_parser(-> { next_token })
      end

      # Parse tokens yielded by `receiver.method_id`.
      # @rbs (untyped receiver, Symbol method_id) -> untyped
      def yyparse(receiver, method_id)
        stream = Enumerator.new do |tokens|
          receiver.__send__(method_id) { |token| tokens << token }
        end
        drive_parser(-> { stream.next })
      end

      # Supply one token to a caller-driven parser session.
      # Returns `:need_more` after consuming it, `[:accepted, result]` after
      # acceptance, or `[:rejected, result]` after recovery terminates.
      # rubocop:disable Layout/LineLength
      # @rbs (untyped token, ?untyped value, ?untyped location) -> (:need_more | [:accepted, untyped] | [:rejected, untyped])
      # rubocop:enable Layout/LineLength
      def push(token, value = nil, location = nil)
        raise ParseError, "(input):1:1: push requires a token; call finish for EOF" if token.nil? || token == false

        run_push_driver do
          start_push_session
          if @repair_policy
            enqueue_or_assign_repair_input(repair_input(token, value, location))
          else
            @lookahead = internal_token_id(token)
            @lookahead_value = value
            @lookahead_location = location
            token_display = token_to_str(@lookahead)
            @runtime_lookahead_token_display = token_display
            trace("read #{token_display}") if @yydebug
          end
          run_push_lookahead
        end
      end

      # Supply EOF to a caller-driven parser session and return its result.
      # @rbs (?location: untyped) -> untyped
      def finish(location: nil)
        run_push_driver do
          start_push_session
          if @repair_policy
            enqueue_or_assign_repair_input(
              RepairInput.new(token_id: EOF_TOKEN, token_name: token_to_str(EOF_TOKEN), value: nil, location: location)
            )
          else
            @lookahead = EOF_TOKEN
            @lookahead_value = nil
            @lookahead_location = location
            token_display = token_to_str(@lookahead)
            @runtime_lookahead_token_display = token_display
            trace("read #{token_display}") if @yydebug
          end
          outcome = run_push_lookahead
          return outcome.fetch(1) if outcome.is_a?(Array)

          raise ParseError, "(input):1:1: parser requested input after EOF"
        end
      end

      # Discard a caller-driven session so this parser can accept a new one.
      # @rbs () -> nil
      def reset_push
        ensure_runtime_initialized!
        @runtime_observation_mutex.synchronize do
          ensure_driver_available_without_lock!
          @push_status = :idle
          @source = nil
          @state_stack = []
          install_value_stack([])
          @location_stack = nil
          @lookahead = NO_LOOKAHEAD
          @lookahead_value = nil
          @lookahead_location = nil
          @runtime_lookahead_token_display = nil
          @repair_input_buffer = nil
          @repair_selected = false
        end
        nil
      end

      # Override in pull parsers. Return `[token, value]`,
      # `[token, value, location]`, `false`, or `nil`.
      # @rbs () -> ([untyped, untyped] | [untyped, untyped, untyped] | false | nil)
      def next_token
        raise NotImplementedError, "(input):1:1: next_token must be implemented"
      end

      # Override to recover from syntax errors. The default raises unless a
      # bounded automatic repair has already been selected.
      # @rbs (Integer token_id, untyped value, Array[untyped] value_stack) -> untyped
      def on_error(token_id, value, _value_stack)
        return if @repair_selected
        return if cst_enabled?

        expected = expected_tokens
        token_name = token_to_str(token_id)
        state = @state_stack.last
        configured = parser_tables.fetch(:error_messages, EMPTY_ROW)[state]
        error_id, detail = configured_error_message(configured)
        raise ParseError.new(
          token_id: token_id,
          token_name: token_name,
          token_value: value,
          expected_tokens: expected,
          location: @lookahead_location,
          state: state,
          suggestions: token_suggestions(token_name, expected),
          error_id: error_id,
          detail: detail
        )
      end

      # Called after an ordinary input token is shifted. Override to observe
      # the internal token id, semantic value, and destination state.
      # @rbs (Integer token_id, untyped value, Integer state) -> void
      def on_shift(_token_id, _value, _state); end

      # Location-aware shift observer. The compatible hook above retains its
      # original signature and runs first.
      # @rbs (Integer token_id, untyped value, Integer state, untyped location) -> void
      def on_shift_location(_token_id, _value, _state, _location); end

      # Called after a production's semantic action and goto are committed.
      # Override to observe its id, RHS values, and semantic result.
      # @rbs (Integer production_id, Array[untyped] values, untyped result) -> void
      def on_reduce(_production_id, _values, _result); end

      # Location-aware reduction observer.
      # @rbs (Integer production_id, Array[untyped] values, untyped result,
      #   Array[untyped] locations, untyped result_location) -> void
      def on_reduce_location(_production_id, _values, _result, _locations, _result_location); end

      # Called after the synthetic error token enters a recovery state.
      # The payload describes the original error before recovery popped stacks.
      # @rbs (Integer token_id, untyped value, Array[untyped] value_stack) -> void
      def on_error_recover(_token_id, _value, _value_stack); end

      # Location-aware recovery observer.
      # @rbs (Integer token_id, untyped value, Array[untyped] value_stack,
      #   untyped location, Integer state) -> void
      def on_error_recover_location(_token_id, _value, _value_stack, _location, _state); end

      # Called when yacc recovery discards an application token.
      # @rbs (Integer token_id, untyped value, untyped location, Symbol reason) -> void
      def on_discard(_token_id, _value, _location, _reason); end

      # Install an opt-in value formatter for human-readable yydebug traces.
      # @rbs ((^(untyped) -> untyped)? printer) -> (^(untyped) -> untyped)?
      def trace_value_printer=(printer)
        ensure_runtime_initialized!
        unless printer.nil? || printer.respond_to?(:call)
          raise ArgumentError, "trace value printer must respond to call or be nil"
        end

        @trace_value_printer = printer
      end

      # Called once after a repair is selected and before its edited token
      # prefix is replayed through normal parser actions.
      # @rbs (RepairPlan plan) -> void
      def on_repair(_plan); end

      # Return a human-readable name for an internal token id.
      # @rbs (Integer token_id) -> String
      def token_to_str(token_id)
        return @unknown_token_name || token_id.to_s if token_id == @unknown_token_id

        parser_tables.fetch(:token_names).fetch(token_id, token_id.to_s)
      end

      # Enter error recovery from a semantic action without calling `on_error`.
      # @rbs () -> nil
      def yyerror
        @semantic_error = true
        nil
      end

      # Leave error recovery immediately.
      # @rbs () -> nil
      def yyerrok
        @recovery_shifts = 0
        nil
      end

      # Accept immediately after the current semantic action completes.
      # @rbs () -> nil
      def yyaccept
        @accept_requested = true
        nil
      end

      # Return token names accepted in the current parser state.
      # @rbs () -> Array[String]
      def expected_tokens
        ensure_runtime_initialized!
        return expected_tokens_exact if parser_tables[:exact_expected_tokens]
        return [] if @state_stack.empty?

        state = @state_stack.last
        parser_tables.fetch(:token_names).keys.filter_map do |token_id|
          action = table_lookup(parser_tables.fetch(:actions), state, token_id) || default_action(state) || ERROR_ACTION
          token_to_str(token_id) unless error_action?(action) || token_id == ERROR_TOKEN
        end
      end

      # Return token names that survive all required default reductions.
      # Semantic actions are not evaluated during this lookahead correction.
      # @rbs () -> Array[String]
      def expected_tokens_exact
        ensure_runtime_initialized!
        return [] if @state_stack.empty?

        parser_tables.fetch(:token_names).keys.filter_map do |token_id|
          next if token_id == ERROR_TOKEN

          token_to_str(token_id) if exact_lookahead_accepted?(token_id)
        end
      end

      # Return the location of a one-based RHS position or named reference
      # while a semantic action is running.
      # @rbs (Integer | Symbol | String reference) -> untyped
      def loc(reference)
        locations = @semantic_locations
        raise ParseError, "(runtime):1:1: loc is only available inside a semantic action" unless locations

        index = if reference.is_a?(Integer)
                  raise ArgumentError, "location index must be positive" unless reference.positive?

                  reference - 1
                else
                  names = @semantic_location_names || EMPTY_LOCATION_NAMES
                  names.fetch(reference.to_sym) do
                    raise ArgumentError, "unknown named location #{reference.inspect}"
                  end
                end
        locations.fetch(index) { raise ArgumentError, "location index #{reference.inspect} is outside the RHS" }
      end

      # Return the synthesized span of the reduction being evaluated.
      # @rbs () -> untyped
      def result_loc
        unless @semantic_locations
          raise ParseError, "(runtime):1:1: result_loc is only available inside a semantic action"
        end

        @semantic_result_location
      end

      private

      # Racc-generated parsers commonly define an application initializer
      # without calling super. Complete only missing runtime state so those
      # initializers retain values they deliberately configured.
      # @rbs () -> void
      def ensure_runtime_initialized!
        return if defined?(@runtime_observation_mutex) && @runtime_observation_mutex

        limits = if defined?(@resource_limits) && @resource_limits.is_a?(ResourceLimits)
                   @resource_limits
                 else
                   ResourceLimits.new
                 end
        initialize_runtime_state(limits, preserve_existing: true)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      # The explicit branches keep every runtime ivar typed while preserving application-owned values.
      # @rbs (ResourceLimits resource_limits, preserve_existing: bool) -> void
      def initialize_runtime_state(resource_limits, preserve_existing:)
        @resource_limits = resource_limits unless preserve_existing && defined?(@resource_limits)
        @yydebug = false unless preserve_existing && defined?(@yydebug)
        @yydebug_output = $stderr unless preserve_existing && defined?(@yydebug_output)
        @source = nil unless preserve_existing && defined?(@source)
        @state_stack = [] unless preserve_existing && defined?(@state_stack)
        install_value_stack([]) unless preserve_existing && defined?(@value_stack)
        @location_stack = nil unless preserve_existing && defined?(@location_stack)
        @lookahead = NO_LOOKAHEAD unless preserve_existing && defined?(@lookahead)
        @lookahead_value = nil unless preserve_existing && defined?(@lookahead_value)
        @lookahead_location = nil unless preserve_existing && defined?(@lookahead_location)
        @recovery_shifts = 0 unless preserve_existing && defined?(@recovery_shifts)
        @semantic_error = false unless preserve_existing && defined?(@semantic_error)
        @accept_requested = false unless preserve_existing && defined?(@accept_requested)
        @unknown_token_id = nil unless preserve_existing && defined?(@unknown_token_id)
        @push_status = :idle unless preserve_existing && defined?(@push_status)
        @driver_status = :idle unless preserve_existing && defined?(@driver_status)
        @runtime_driver_thread = nil unless preserve_existing && defined?(@runtime_driver_thread)
        @runtime_observers = nil unless preserve_existing && defined?(@runtime_observers)
        @runtime_event_sequence = 0 unless preserve_existing && defined?(@runtime_event_sequence)
        @runtime_lookahead_token_display = nil unless preserve_existing && defined?(@runtime_lookahead_token_display)
        @runtime_observation_mutex = Mutex.new unless preserve_existing && defined?(@runtime_observation_mutex)
        @repair_policy = nil unless preserve_existing && defined?(@repair_policy)
        @repair_input_buffer = nil unless preserve_existing && defined?(@repair_input_buffer)
        @repair_selected = false unless preserve_existing && defined?(@repair_selected)
        @semantic_locations = nil unless preserve_existing && defined?(@semantic_locations)
        @semantic_location_names = nil unless preserve_existing && defined?(@semantic_location_names)
        @semantic_result_location = nil unless preserve_existing && defined?(@semantic_result_location)
        @trace_value_printer = nil unless preserve_existing && defined?(@trace_value_printer)
        @sync_recovery_context = nil unless preserve_existing && defined?(@sync_recovery_context)
        @sync_recovery_token_data = nil unless preserve_existing && defined?(@sync_recovery_token_data)
        @sync_recovery_observers = nil unless preserve_existing && defined?(@sync_recovery_observers)
        @cst_errors = [] unless preserve_existing && defined?(@cst_errors)
        @recovery_attempts = 0 unless preserve_existing && defined?(@recovery_attempts)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # @rbs (ResourceLimits resource_limits) -> void
      def validate_resource_limits!(resource_limits)
        return if resource_limits.is_a?(ResourceLimits)

        raise ArgumentError, "resource_limits must be an Ibex::Runtime::ResourceLimits"
      end

      # Keep the two historical value-stack names as read-compatible aliases.
      # Applications must not mutate or replace these internal arrays.
      # @rbs (Array[untyped] values) -> void
      def install_value_stack(values)
        @value_stack = values
        @vstack = values
        @racc_vstack = values
      end

      # @rbs (Integer token_id) -> bool
      def exact_lookahead_accepted?(token_id)
        stack = @state_stack.dup
        seen = {} #: Hash[Array[Integer], bool]
        remaining = exact_lookahead_step_budget(stack.length)
        loop do
          return false unless remaining.positive?
          return false if seen.key?(stack)

          remaining -= 1
          seen[stack.dup.freeze] = true
          state = stack.last
          action = table_lookup(parser_tables.fetch(:actions), state, token_id) || default_action(state) || ERROR_ACTION
          case action.first
          when :shift, :accept then return true
          when :error then return false
          end
          return false unless action.first == :reduce
          return false unless exact_reduction_applied?(stack, action.fetch(1))
        end
      end

      # @rbs (Integer stack_depth) -> Integer
      def exact_lookahead_step_budget(stack_depth)
        tables = parser_tables
        production_count = tables.fetch(:productions).length
        unless production_count.is_a?(Integer)
          raise ParseError, "(tables):1:1: parser table production count must be an Integer"
        end

        (stack_depth + parser_state_count(tables) + 1) * (production_count + 1)
      end

      # @rbs (Hash[Symbol, untyped] tables) -> Integer
      def parser_state_count(tables)
        state_count = tables[:state_count]
        return state_count if state_count.is_a?(Integer)

        actions = tables.fetch(:actions)
        state_count = actions.respond_to?(:row_count) ? actions.row_count : actions.length
        return state_count if state_count.is_a?(Integer)

        raise ParseError, "(tables):1:1: parser table state count must be an Integer"
      end

      # @rbs (Array[Integer] stack, Integer production_id) -> bool
      def exact_reduction_applied?(stack, production_id)
        production = parser_tables.fetch(:productions).fetch(production_id)
        length = production.fetch(:length)
        return false if length >= stack.length

        stack.pop(length)
        target = table_lookup(parser_tables.fetch(:gotos), stack.last, production.fetch(:lhs))
        return false unless target

        stack << target
        true
      end

      # @rbs (^() -> untyped source, ?initial_state: Integer?) -> untyped
      def drive_parser(source, initial_state: nil)
        ensure_runtime_initialized!
        @runtime_observation_mutex.synchronize do
          ensure_driver_available_without_lock!
          if @push_status == :active
            raise ParseError, "(input):1:1: cannot start another parser driver during an active push session"
          end

          @driver_status = :pull
          @runtime_driver_thread = Thread.current
        end

        begin
          prepare_parse(source, initial_state: initial_state)
          loop do
            action = action_for_current_state
            outcome = perform(action)
            case outcome[0]
            when :accepted, :done then return outcome[1]
            end
          end
        ensure
          @source = nil
          release_driver
        end
      end

      # @rbs () -> void
      def start_push_session
        if @push_status == :finished
          raise ParseError, "(input):1:1: push session is finished; call reset_push before supplying more input"
        end
        return if @push_status == :active

        prepare_parse(-> { raise ParseError, "(input):1:1: push session needs another token" })
        @push_status = :active
      end

      # @rbs () -> (:need_more | [:accepted, untyped] | [:rejected, untyped])
      def run_push_lookahead
        loop do
          outcome = perform(action_for_current_state)
          return :need_more if outcome.first == :repair_pending

          case outcome.first
          when :accepted
            finish_push_session
            return [:accepted, outcome.fetch(1)]
          when :done
            finish_push_session
            return [:rejected, outcome.fetch(1)]
          end
          next unless @lookahead.equal?(NO_LOOKAHEAD)

          repair_buffer = @repair_input_buffer
          next if repair_buffer && !repair_buffer.empty?

          return :need_more
        end
      end

      # @rbs () { () -> untyped } -> untyped
      def run_push_driver
        ensure_runtime_initialized!
        @runtime_observation_mutex.synchronize do
          ensure_driver_available_without_lock!
          @driver_status = :push
          @runtime_driver_thread = Thread.current
        end
        begin
          yield
        rescue StandardError
          finish_push_session
          raise
        ensure
          release_driver
        end
      end

      # @rbs () -> void
      def ensure_driver_available_without_lock!
        return if @driver_status == :idle

        raise ParseError, "(input):1:1: parser driver is already running"
      end

      # @rbs () -> void
      def release_driver
        @runtime_observation_mutex.synchronize do
          @driver_status = :idle
          @runtime_driver_thread = nil
        end
      end

      # @rbs () -> void
      def finish_push_session
        @push_status = :finished
        @source = nil
        @lookahead = NO_LOOKAHEAD
        @lookahead_location = nil
        @repair_input_buffer = nil
        @repair_selected = false
        clear_sync_recovery
      end

      # @rbs (^() -> untyped source, ?initial_state: Integer?) -> void
      def prepare_parse(source, initial_state: nil)
        tables = validate_parser_table_format!
        initial_state = resolve_initial_state(tables, initial_state)

        @source = source
        @state_stack = [initial_state]
        install_value_stack([])
        @location_stack = track_locations?(tables) ? [] : nil
        @lookahead = NO_LOOKAHEAD
        @lookahead_value = nil
        @lookahead_location = nil
        @runtime_lookahead_token_display = nil
        reset_parse_recovery_state
        @accept_requested = false
        @unknown_token_id = nil
        @cst_errors = []
        @recovery_attempts = 0
        trace("start state #{initial_state}") if @yydebug
        @runtime_event_sequence = 0
        return unless @runtime_observers

        emit_runtime_event(
          :start,
          {
            "driver" => @driver_status.to_s,
            "initial_state" => initial_state,
            "table_format_version" => tables.fetch(:format_version),
            "grammar_digest" => tables[:grammar_digest],
            "state_count" => tables[:state_count],
            "production_count" => tables[:production_count]
          }
        )
      end

      # @rbs () -> void
      def reset_parse_recovery_state
        @recovery_shifts = 0
        @semantic_error = false
        @repair_input_buffer = @repair_policy ? [] : nil
        @repair_selected = false
        clear_sync_recovery
      end

      # @rbs (Hash[Symbol, untyped] tables, Integer? requested) -> Integer
      def resolve_initial_state(tables, requested)
        initial_state = requested || tables[:initial_state] || 0
        return initial_state if initial_state.is_a?(Integer) &&
                                initial_state.between?(0, parser_state_count(tables) - 1)

        raise ParseError, "(tables):1:1: parser initial state #{initial_state.inspect} is invalid"
      end

      # @rbs () -> Hash[Symbol, untyped]
      def validate_parser_table_format!
        tables = parser_tables
        unless tables.key?(:format_version)
          raise ParseError,
                "(tables):1:1: parser tables for #{self.class} are missing :format_version; " \
                "regenerate the parser with the installed Ibex version"
        end

        actual = tables.fetch(:format_version)
        unless SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS.include?(actual)
          raise ParseError,
                "(tables):1:1: unsupported parser table format version #{actual.inspect} for #{self.class}; " \
                "runtime supports #{SUPPORTED_PARSER_TABLE_FORMAT_VERSIONS.join(', ')}; " \
                "regenerate the parser with the installed Ibex version"
        end

        validate_composition_action_contract!(tables) if actual == PARSER_TABLE_FORMAT_VERSION
        tables
      end

      # @rbs (Hash[Symbol, untyped] tables) -> void
      def validate_composition_action_contract!(tables)
        tables.fetch(:productions).each_with_index do |production, index|
          next unless production[:composition_action] == true
          next if production[:location_action] == true && generated_action_symbol?(production[:action])

          raise ParseError,
                "(tables):1:1: parser table format version 3 production #{index} has an inconsistent " \
                ":composition_action marker; a generated action Symbol with :location_action is required"
        end
      end

      # @rbs () -> untyped
      def action_for_current_state
        if @lookahead.equal?(NO_LOOKAHEAD)
          state = @state_stack.last
          eager = parser_tables.fetch(:eager_reductions, EMPTY_ROW)[state]
          return eager if eager
        end
        read_lookahead if @lookahead.equal?(NO_LOOKAHEAD)
        return SYNC_RECOVER_ACTION if sync_recovery_active?

        state = @state_stack.last
        return ERROR_ACTION unless parser_tables.fetch(:token_names).key?(@lookahead)

        explicit = table_lookup(parser_tables.fetch(:actions), state, @lookahead)
        return explicit if explicit

        default_action(state) || ERROR_ACTION
      end

      # @rbs (untyped action) -> untyped
      def perform(action)
        case action.first
        when :shift then shift(action.fetch(1))
        when :reduce then reduce(action.fetch(1))
        when :accept
          result = finalize_cst(@value_stack.last)
          emit_accept_event(EventSanitizer.value(result), "table") if @runtime_observers
          [:accepted, result]
        when :error then recover
        when :sync_recover then continue_sync_recovery
        else raise ParseError, "(tables):1:1: unknown parser action #{action.inspect}"
        end
      end

      # @rbs (Integer next_state) -> untyped
      def shift(next_state)
        token_id = @lookahead
        value = @lookahead_value
        location = @lookahead_location
        token_display = token_to_str(token_id)
        trace("shift #{token_display}#{trace_value_suffix(value, token_id)} -> state #{next_state}") if @yydebug
        event_observers = runtime_observer_snapshot if @runtime_observers
        event_data = if event_observers
                       runtime_token_data(
                         token_id: token_id,
                         token_display: token_display,
                         value: value,
                         location: location,
                         state: next_state
                       ).merge("from_state" => @state_stack.last).freeze
                     end
        ensure_stack_capacity!
        @state_stack << next_state
        push_location(location)
        @value_stack << value
        @lookahead = NO_LOOKAHEAD
        @lookahead_location = nil
        @runtime_lookahead_token_display = nil
        @recovery_shifts -= 1 if @recovery_shifts.positive?
        on_shift(token_id, value, next_state)
        on_shift_location(token_id, value, next_state, location)
        emit_runtime_event(:shift, event_data, observers: event_observers) if event_data
        CONTINUE_OUTCOME
      end

      # @rbs (Integer production_id) -> untyped
      def reduce(production_id)
        production = parser_tables.fetch(:productions).fetch(production_id)
        length = production.fetch(:length)
        event_observers = runtime_observer_snapshot if @runtime_observers
        pre_state = @state_stack.last if event_observers
        values = @value_stack.last(length)
        locations = pop_reduction_locations(length)
        hook_values = values.dup
        @state_stack.pop(length)
        @value_stack.pop(length)
        post_state = @state_stack.last if event_observers
        location = LocationSpan.for_reduction(locations, lookahead: @lookahead_location)
        result = reduction_value(production_id, production, values, locations, location)
        next_state = table_lookup(parser_tables.fetch(:gotos), @state_stack.last, production.fetch(:lhs))
        raise ParseError, "(tables):1:1: missing goto for production #{production_id}" if next_state.nil?

        ensure_stack_capacity!
        push_reduction_result(next_state, result, location)
        trace_reduction(production_id, length, production.fetch(:lhs), result, next_state)
        event_data = build_reduce_event_data(
          event_observers, production_id, production, length, pre_state, post_state, next_state, result, location
        )
        on_reduce(production_id, hook_values, result)
        on_reduce_location(production_id, hook_values, result, locations.dup, location)
        emit_runtime_event(:reduce, event_data, observers: event_observers) if event_data
        return accept_reduction(result) if @accept_requested
        return recover(report: false) if @semantic_error

        CONTINUE_OUTCOME
      end

      # @rbs (Integer next_state, untyped result, untyped location) -> void
      def push_reduction_result(next_state, result, location)
        @state_stack << next_state
        push_location(location)
        @value_stack << result
      end

      # @rbs (Integer production_id, Integer length, Integer lhs, untyped result, Integer next_state) -> void
      def trace_reduction(production_id, length, lhs, result, next_state)
        return unless @yydebug

        trace("reduce #{production_id} (#{length})#{trace_value_suffix(result, lhs)} -> state #{next_state}")
      end

      # @rbs (Array[Proc]? observers, Integer production_id, Hash[Symbol, untyped] production, Integer length,
      #   Integer? pre_state, Integer? post_state, Integer next_state, untyped result,
      #   LocationSpan? location) -> Hash[String, untyped]?
      def build_reduce_event_data(
        observers, production_id, production, length, pre_state, post_state, next_state, result, location
      )
        return unless observers

        runtime_reduce_data(
          production_id, production, length, pre_state, post_state, next_state, result, location
        )
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Integer length,
      #   Integer? pre_state, Integer? post_state, Integer next_state, untyped result,
      #   LocationSpan? location) -> Hash[String, untyped]
      def runtime_reduce_data(production_id, production, length, pre_state, post_state, next_state, result, location)
        {
          "production_id" => production_id,
          "lhs" => production.fetch(:lhs),
          "rhs_length" => length,
          "pre_state" => pre_state,
          "post_state" => post_state,
          "goto_state" => next_state,
          "result" => EventSanitizer.value(result),
          "location" => EventSanitizer.location(location)
        }.freeze
      end

      # @rbs (untyped result) -> [:accepted, untyped]
      def accept_reduction(result)
        result = finalize_cst(result)
        emit_accept_event(EventSanitizer.value(result), "semantic") if @runtime_observers
        [:accepted, result]
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Array[untyped] values,
      #   Array[untyped] locations, LocationSpan? location) -> untyped
      def reduction_value(production_id, production, values, locations, location)
        previous_locations = @semantic_locations
        previous_names = @semantic_location_names
        previous_result_location = @semantic_result_location
        action = production[:action]
        return actionless_reduction_value(production_id, production, values, locations, location) unless action

        context_length = production.fetch(:location_context_length, 0)
        action_locations = if context_length.positive?
                             (@location_stack || []).last(context_length)
                           else
                             locations
                           end
        @semantic_locations = action_locations
        @semantic_location_names = production.fetch(:location_names, EMPTY_LOCATION_NAMES)
        @semantic_result_location = location
        arguments = [values, @value_stack.dup, locations, (@location_stack || []).dup, location]
        arguments = arguments.take(2) unless generated_location_action?(production, action)
        arguments << @lookahead_location if generated_composition_action?(production, action)
        action.respond_to?(:call) ? instance_exec(*arguments, &action) : __send__(action, *arguments)
      ensure
        @semantic_locations = previous_locations
        @semantic_location_names = previous_names
        @semantic_result_location = previous_result_location
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Array[untyped] values,
      #   Array[untyped] locations, LocationSpan? location) -> untyped
      def actionless_reduction_value(production_id, production, values, locations, location)
        return values.first unless cst_enabled?

        cst_reduction_value(production_id, production, values, locations, location)
      end

      # @rbs (Hash[Symbol, untyped] production, untyped action) -> bool
      def generated_location_action?(production, action)
        parser_tables.fetch(:format_version) >= 2 &&
          production[:location_action] == true &&
          generated_action_symbol?(action)
      end

      # @rbs (Hash[Symbol, untyped] production, untyped action) -> bool
      def generated_composition_action?(production, action)
        parser_tables.fetch(:format_version) == PARSER_TABLE_FORMAT_VERSION &&
          production[:composition_action] == true &&
          generated_location_action?(production, action)
      end

      # @rbs (untyped action) -> bool
      def generated_action_symbol?(action)
        action.is_a?(Symbol) && action.to_s.match?(GENERATED_ACTION_NAME)
      end

      # @rbs () -> bool
      def cst_enabled?
        parser_tables[:cst] == true
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Array[untyped] values,
      #   Array[untyped] locations, LocationSpan? location) -> CST::Node
      def cst_reduction_value(production_id, production, values, locations, location)
        rhs = production.fetch(:rhs)
        children = @cst_errors.dup #: Array[CST::Token | CST::Node]
        @cst_errors.clear
        rhs.each_with_index do |symbol_id, index|
          value = values[index]
          child = if value.is_a?(CST::Token) || value.is_a?(CST::Node)
                    value
                  else
                    cst_token(symbol_id, value, locations[index])
                  end
          children << child
        end
        CST::Node.new(
          symbol: cst_symbol_name(production.fetch(:lhs)), production_id: production_id,
          children: children, location: location
        )
      end

      # @rbs (Integer symbol_id, untyped value, untyped location) -> CST::Token
      def cst_token(symbol_id, value, location)
        symbol = cst_symbol_name(symbol_id)
        repair = cst_location_value(location, :ibex_repair)
        trivia = cst_location_value(location, :leading_trivia)
        leading = trivia.is_a?(Array) ? trivia.grep(CST::Trivia) : [] #: Array[CST::Trivia]
        if repair == :insert
          CST::Missing.new(symbol: symbol, value: value, location: location, leading_trivia: leading)
        elsif repair == :replace || symbol == "error"
          CST::Error.new(symbol: symbol, value: value, location: location, reason: repair || :syntax,
                         leading_trivia: leading)
        else
          CST::Token.new(symbol: symbol, value: value, location: location, leading_trivia: leading)
        end
      end

      # @rbs (Integer token_id, untyped value, untyped location, Symbol reason) -> void
      def capture_cst_error(token_id, value, location, reason)
        return unless cst_enabled?
        return if token_id == EOF_TOKEN

        @cst_errors << CST::Error.new(
          symbol: token_to_str(token_id), value: value, location: location, reason: reason
        )
      end

      # @rbs (untyped value) -> CST::Node
      def finalize_cst(value)
        return value unless cst_enabled?

        node = if value.is_a?(CST::Node)
                 value
               else
                 child = if value.is_a?(CST::Token)
                           value
                         else
                           CST::Token.new(symbol: parser_tables.fetch(:cst_start), value: value, location: nil)
                         end
                 CST::Node.new(
                   symbol: parser_tables.fetch(:cst_start), production_id: -1,
                   children: @cst_errors + [child], location: child.location
                 )
               end
        @cst_errors.clear
        return node unless respond_to?(:take_cst_trailing_trivia, true)

        trailing = __send__(:take_cst_trailing_trivia)
        trailing.empty? ? node : node.with_trailing_trivia(trailing)
      end

      # @rbs () -> CST::Node
      def failed_cst
        capture_cst_error(@lookahead, @lookahead_value, @lookahead_location, :syntax) if @cst_errors.empty?
        CST::Node.new(
          symbol: parser_tables.fetch(:cst_start), production_id: -1,
          children: @cst_errors.dup, location: @lookahead_location
        )
      end

      # @rbs (ParseError error) -> CST::Node
      def cst_lexical_failure(error)
        error_node = CST::Error.new(
          symbol: "lexer input", value: error.token_value, location: error.location, reason: :lexical
        )
        CST::Node.new(
          symbol: parser_tables.fetch(:cst_start), production_id: -1,
          children: [error_node], location: error.location
        )
      end

      # @rbs (Integer symbol_id) -> String
      def cst_symbol_name(symbol_id)
        parser_tables.fetch(:symbol_names).fetch(symbol_id)
      end

      # @rbs (untyped location, Symbol key) -> untyped
      def cst_location_value(location, key)
        return location[key] || location[key.to_s] if location.is_a?(Hash)
        return location.public_send(key) if location.respond_to?(key)

        nil
      end

      # @rbs (?report: bool) -> untyped
      def recover(report: true)
        @semantic_error = false
        return continue_recovery if @recovery_shifts.positive?

        begin_recovery(report)
      end

      # @rbs () -> untyped
      def continue_recovery
        return reject_recovery_eof if @lookahead == EOF_TOKEN

        token_display = token_to_str(@lookahead)
        event_observers = runtime_observer_snapshot if @runtime_observers
        event_data = runtime_discard_data(token_display) if event_observers
        trace("discard #{token_display} during recovery") if @yydebug
        on_discard(@lookahead, @lookahead_value, @lookahead_location, :recovery)
        @lookahead = NO_LOOKAHEAD
        @lookahead_location = nil
        @runtime_lookahead_token_display = nil
        emit_runtime_event(:discard, event_data, observers: event_observers) if event_data
        CONTINUE_OUTCOME
      end

      # @rbs () -> [:done, CST::Node?]
      def reject_recovery_eof
        if @runtime_observers
          observers = runtime_observer_snapshot
          data = runtime_current_token_data
          emit_reject_event("eof_during_recovery", data, observers: observers)
        end
        [:done, cst_enabled? ? failed_cst : nil]
      end

      # @rbs (String token_display) -> Hash[String, untyped]
      def runtime_discard_data(token_display)
        runtime_token_data(
          token_id: @lookahead,
          token_display: token_display,
          value: @lookahead_value,
          location: @lookahead_location,
          state: @state_stack.last
        ).merge("reason" => "recovery").freeze
      end

      # @rbs (bool report) -> untyped
      def begin_recovery(report)
        consume_recovery_attempt!
        repair = report ? selected_repair : nil
        return REPAIR_PENDING_OUTCOME if repair.equal?(RepairSearch::NEED_INPUT)

        context = recovery_context(report)
        capture_cst_error(context[:token_id], context[:value], context[:location], context[:reason].to_sym)
        token_data, recovery_observers = publish_error_context(context)
        notify_error_handler(context, repair) if report
        return commit_repair(repair) if repair.is_a?(RepairPlan)

        fallback_recovery(context, token_data, recovery_observers)
      end

      # @rbs (bool report) -> Hash[Symbol, untyped]
      def recovery_context(report)
        {
          token_id: @lookahead,
          value: @lookahead_value,
          token_display: @runtime_lookahead_token_display,
          location: @lookahead_location,
          value_stack: @value_stack.dup,
          state: @state_stack.last,
          reason: report ? "syntax" : "semantic"
        }
      end

      # @rbs (Hash[Symbol, untyped] context) -> [Hash[String, untyped]?, Array[Proc]?]
      def publish_error_context(context)
        error_observers = runtime_observer_snapshot if @runtime_observers
        if error_observers
          token_data = runtime_original_token_data(
            context[:token_id], context[:token_display], context[:value], context[:location], context[:state]
          )
          emit_runtime_event(
            :error, token_data.merge("reason" => context[:reason]), observers: error_observers
          )
        end
        [token_data, (runtime_observer_snapshot if @runtime_observers)]
      end

      # @rbs (Hash[Symbol, untyped] context, untyped repair) -> void
      def notify_error_handler(context, repair)
        @repair_selected = repair.is_a?(RepairPlan)
        begin
          on_error(context[:token_id], context[:value], context.fetch(:value_stack).dup)
        ensure
          @repair_selected = false
        end
      end

      # @rbs (RepairPlan repair) -> [:continue]
      def commit_repair(repair)
        on_repair(repair)
        apply_repair(repair)
        CONTINUE_OUTCOME
      end

      # @rbs (Hash[Symbol, untyped] context, Hash[String, untyped]? token_data,
      #   Array[Proc]? recovery_observers) -> untyped
      def fallback_recovery(context, token_data, recovery_observers)
        state_stack = @state_stack.dup if sync_recovery_configured?
        value_stack = @value_stack.dup if state_stack
        location_stack = @location_stack&.dup if state_stack
        unless shift_error_token
          if state_stack
            @state_stack = state_stack
            install_value_stack(value_stack || [])
            @location_stack = location_stack
            return begin_sync_recovery(context, token_data, recovery_observers)
          end

          return reject_without_recovery(
            context[:token_id], context[:token_display], context[:value], context[:location], context[:state],
            token_data, recovery_observers
          )
        end

        @recovery_shifts = RECOVERY_SHIFTS
        finish_recovery(
          context[:token_id], context[:token_display], context[:value], context[:location], context[:state],
          context[:value_stack], token_data, context[:reason], recovery_observers
        )
      end

      # @rbs (untyped token_id, untyped token_display, untyped value, untyped location,
      #   Integer state) -> Hash[String, untyped]
      def runtime_original_token_data(token_id, token_display, value, location, state)
        runtime_token_data(
          token_id: token_id,
          token_display: token_display,
          value: value,
          location: location,
          state: state
        )
      end

      # @rbs (untyped token_id, untyped token_display, untyped value, untyped location,
      #   Integer original_state, Hash[String, untyped]? token_data,
      #   Array[Proc]? observers) -> [:done, CST::Node?]
      def reject_without_recovery(token_id, token_display, value, location, original_state, token_data, observers)
        if observers
          reject_data = token_data || runtime_original_token_data(
            token_id, token_display, value, location, original_state
          )
          emit_reject_event(
            "no_recovery_state",
            reject_data.merge("state" => @state_stack.last),
            observers: observers
          )
        end
        [:done, cst_enabled? ? failed_cst : nil]
      end

      # @rbs (untyped token_id, untyped token_display, untyped value, untyped location,
      #   Integer original_state, Array[untyped] value_stack, Hash[String, untyped]? token_data,
      #   String reason, Array[Proc]? observers) -> [:continue]
      def finish_recovery(
        token_id, token_display, value, location, original_state, value_stack, token_data, reason, observers
      )
        recover_data = if observers
                         token_data || runtime_original_token_data(
                           token_id, token_display, value, location, original_state
                         )
                       end
        on_error_recover(token_id, value, value_stack)
        on_error_recover_location(token_id, value, value_stack, location, @state_stack.last)
        if recover_data
          emit_runtime_event(
            :recover,
            recover_data.merge(
              "from_state" => original_state,
              "state" => @state_stack.last,
              "reason" => reason
            ),
            observers: observers
          )
        end
        CONTINUE_OUTCOME
      end

      # @rbs (token_id: untyped, token_display: untyped, value: untyped,
      #   location: untyped, state: Integer) -> Hash[String, untyped]
      def runtime_token_data(token_id:, token_display:, value:, location:, state:)
        if token_id.equal?(NO_LOOKAHEAD)
          return {
            "state" => state,
            "token_id" => nil,
            "token" => nil,
            "value" => nil,
            "location" => nil
          }.freeze
        end

        {
          "state" => state,
          "token_id" => token_id,
          "token" => EventSanitizer.value(token_display),
          "value" => EventSanitizer.value(value),
          "location" => EventSanitizer.location(location)
        }.freeze
      end

      # @rbs () -> Hash[String, untyped]
      def runtime_current_token_data
        runtime_token_data(
          token_id: @lookahead,
          token_display: @runtime_lookahead_token_display,
          value: @lookahead_value,
          location: @lookahead_location,
          state: @state_stack.last
        )
      end

      # @rbs (untyped result_summary, String reason) -> void
      def emit_accept_event(result_summary, reason)
        emit_runtime_event(
          :accept,
          { "state" => @state_stack.last, "result" => result_summary, "reason" => reason }
        )
      end

      # @rbs (String reason, Hash[String, untyped] token_data, ?observers: Array[Proc]?) -> void
      def emit_reject_event(reason, token_data, observers: runtime_observer_snapshot)
        emit_runtime_event(
          :reject,
          token_data.merge("reason" => reason),
          observers: observers
        )
      end

      # @rbs () -> bool
      def shift_error_token
        loop do
          action = table_lookup(parser_tables.fetch(:actions), @state_stack.last, ERROR_TOKEN)
          if action&.first == :shift
            trace("recover: shift error -> state #{action.fetch(1)}") if @yydebug
            ensure_stack_capacity!
            @state_stack << action.fetch(1)
            push_location(@lookahead_location)
            @value_stack << nil
            return true
          end
          return false if @state_stack.length == 1

          trace("recover: pop state #{@state_stack.last}") if @yydebug
          @state_stack.pop
          @value_stack.pop
          @location_stack&.pop
        end
      end

      # @rbs () -> void
      def ensure_stack_capacity!
        observed = @state_stack.length + 1
        limit = @resource_limits.max_stack_depth
        return if observed <= limit

        raise ResourceLimitError.new(
          resource: :stack_depth, limit: limit, observed: observed,
          state: @state_stack.last, location: @lookahead_location
        )
      end

      # @rbs () -> void
      def consume_recovery_attempt!
        @recovery_attempts += 1
        limit = @resource_limits.max_recovery_attempts
        return if @recovery_attempts <= limit

        raise ResourceLimitError.new(
          resource: :recovery_attempts, limit: limit, observed: @recovery_attempts,
          state: @state_stack.last, location: @lookahead_location
        )
      end

      # @rbs () -> (RepairPlan | Object | nil)
      def selected_repair
        policy = @repair_policy
        return unless policy

        tokens, complete = repair_search_tokens(policy)
        RepairSearch.new(parser_tables, policy, tokens, complete: complete).search(@state_stack)
      end

      # @rbs (RepairPolicy policy) -> [Array[RepairInput], bool]
      def repair_search_tokens(policy)
        current = RepairInput.new(
          token_id: @lookahead,
          token_name: @runtime_lookahead_token_display || token_to_str(@lookahead),
          value: @lookahead_value,
          location: @lookahead_location
        )
        buffer = @repair_input_buffer || raise(ParseError, "(repair):1:1: repair input buffer is unavailable")
        while @driver_status == :pull && buffer.length + 1 < policy.max_lookahead &&
              !buffer.last&.eof?
          buffer << repair_input_from_external(read_external_token)
        end
        tokens = ([current] + buffer).take(policy.max_lookahead)
        complete = tokens.any?(&:eof?) || tokens.length >= policy.max_lookahead
        [tokens.freeze, complete]
      end

      # @rbs (RepairPlan plan) -> void
      def apply_repair(plan)
        source = [current_repair_input] + (@repair_input_buffer || [])
        @repair_input_buffer = replay_repair_edits(source, plan.edits)
        clear_repair_lookahead
        @recovery_shifts = 0
        trace("repair cost #{plan.cost}: #{repair_trace(plan)}") if @yydebug
      end

      # @rbs () -> RepairInput
      def current_repair_input
        RepairInput.new(
          token_id: @lookahead,
          token_name: @runtime_lookahead_token_display || token_to_str(@lookahead),
          value: @lookahead_value,
          location: @lookahead_location
        )
      end

      # @rbs (Array[RepairInput] source, Array[RepairEdit] edits) -> Array[RepairInput]
      def replay_repair_edits(source, edits)
        by_position = edits.group_by(&:position)
        repaired = [] #: Array[RepairInput]
        source.each_with_index do |input, position|
          consumed = append_repair_edits(repaired, input, by_position.fetch(position, []))
          repaired << input unless consumed
        end
        by_position.fetch(source.length, []).each do |edit|
          repaired << synthetic_repair_input(edit, value: nil, location: @lookahead_location)
        end
        repaired
      end

      # @rbs (Array[RepairInput] output, RepairInput input, Array[RepairEdit] edits) -> bool
      def append_repair_edits(output, input, edits)
        edits.each do |edit|
          if edit.kind == :insert
            output << synthetic_repair_input(edit, value: nil, location: input.location)
          elsif edit.kind == :replace
            output << synthetic_repair_input(edit, value: input.value, location: input.location)
          end
        end
        edits.any? { |edit| %i[delete replace].include?(edit.kind) }
      end

      # @rbs () -> void
      def clear_repair_lookahead
        @lookahead = NO_LOOKAHEAD
        @lookahead_value = nil
        @lookahead_location = nil
        @runtime_lookahead_token_display = nil
      end

      # @rbs (RepairEdit edit, value: untyped, location: untyped) -> RepairInput
      def synthetic_repair_input(edit, value:, location:)
        location = cst_repair_location(location, edit.kind) if cst_enabled?
        RepairInput.new(token_id: edit.token_id, token_name: edit.token_name, value: value, location: location)
      end

      # @rbs (untyped location, Symbol kind) -> Hash[Symbol, untyped]
      def cst_repair_location(location, kind)
        return location.merge(ibex_repair: kind).freeze if location.is_a?(Hash)

        {
          file: cst_location_value(location, :file),
          line: cst_location_value(location, :line),
          column: cst_location_value(location, :column),
          end_line: cst_location_value(location, :end_line),
          end_column: cst_location_value(location, :end_column),
          origin: location,
          ibex_repair: kind
        }.freeze
      end

      # @rbs (RepairPlan plan) -> String
      def repair_trace(plan)
        plan.edits.map { |edit| "#{edit.kind}(#{edit.token_name}@#{edit.position})" }.join(", ")
      end

      # @rbs () -> void
      def read_lookahead
        return read_repair_lookahead if @repair_policy

        read_compatible_lookahead
      end

      # @rbs () -> void
      def read_repair_lookahead
        buffer = @repair_input_buffer
        input = if buffer&.any?
                  buffer.shift
                else
                  repair_input_from_external(read_external_token)
                end
        assign_repair_input(input)
      end

      # @rbs () -> void
      def read_compatible_lookahead
        token = read_external_token
        if token.nil? || token == false
          @lookahead = EOF_TOKEN
          @lookahead_value = nil
          @lookahead_location = nil
        else
          external_token, @lookahead_value, @lookahead_location = token
          @lookahead = if external_token.nil? || external_token == false
                         EOF_TOKEN
                       else
                         internal_token_id(external_token)
                       end
        end
        token_display = token_to_str(@lookahead)
        @runtime_lookahead_token_display = token_display
        trace("read #{token_display}") if @yydebug
      end

      # @rbs (untyped external_token, untyped value, untyped location) -> RepairInput
      def repair_input(external_token, value, location)
        token_id = parser_tables.fetch(:tokens)[external_token]
        if token_id
          return RepairInput.new(
            token_id: token_id, token_name: token_to_str(token_id), value: value, location: location
          )
        end

        RepairInput.new(
          token_id: -external_token.object_id.abs,
          token_name: external_token.inspect,
          value: value,
          location: location
        )
      end

      # @rbs (untyped token) -> RepairInput
      def repair_input_from_external(token)
        if token.nil? || token == false
          return RepairInput.new(token_id: EOF_TOKEN, token_name: token_to_str(EOF_TOKEN), value: nil, location: nil)
        end

        external_token, value, location = token
        if external_token.nil? || external_token == false
          return RepairInput.new(
            token_id: EOF_TOKEN,
            token_name: token_to_str(EOF_TOKEN),
            value: nil,
            location: location
          )
        end
        repair_input(external_token, value, location)
      end

      # @rbs (RepairInput input) -> void
      def enqueue_or_assign_repair_input(input)
        buffer = @repair_input_buffer || raise(ParseError, "(repair):1:1: repair input buffer is unavailable")
        if @lookahead.equal?(NO_LOOKAHEAD) && buffer.empty?
          assign_repair_input(input)
        else
          buffer << input
        end
      end

      # @rbs (RepairInput input) -> void
      def assign_repair_input(input)
        @lookahead = input.token_id
        @lookahead_value = input.value
        @lookahead_location = input.location
        @runtime_lookahead_token_display = input.token_name
        if input.token_id.negative?
          @unknown_token_id = input.token_id
          @unknown_token_name = input.token_name
        end
        trace("read #{input.token_name}") if @yydebug
      end

      # @rbs () -> untyped
      def read_external_token
        source = @source
        raise ParseError, "(input):1:1: token source is not available" unless source

        source.call
      rescue StopIteration
        false
      end

      # @rbs (untyped external_token) -> Integer
      def internal_token_id(external_token)
        token_id = parser_tables.fetch(:tokens)[external_token]
        return token_id if token_id

        @unknown_token_name = external_token.inspect
        @unknown_token_id = -external_token.object_id.abs
      end

      # @rbs () -> Hash[Symbol, untyped]
      def parser_tables
        self.class.__send__(:parser_tables)
      rescue NoMethodError
        raise ParseError, "(tables):1:1: #{self.class} must define .parser_tables"
      end

      # @rbs (untyped action) -> bool
      def error_action?(action)
        action.nil? || action.first == :error
      end

      # @rbs (untyped configured) -> [String?, String?]
      def configured_error_message(configured)
        return [nil, configured] unless configured.is_a?(Hash)

        error_id = configured[:id] || configured["id"]
        message = configured[:message] || configured["message"]
        [error_id, message]
      end

      # @rbs (String actual, Array[String] expected) -> Array[String]
      def token_suggestions(actual, expected)
        word = normalized_token_word(actual)
        return [] unless word

        threshold = word.length < 5 ? 1 : 2
        expected.filter_map do |candidate|
          candidate_word = normalized_token_word(candidate)
          candidate if candidate_word && edit_distance(word, candidate_word) <= threshold
        end
      end

      # @rbs (String token_name) -> String?
      def normalized_token_word(token_name)
        word = token_name.delete_prefix(":")
        word.upcase if word.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      end

      # @rbs (String left, String right) -> Integer
      def edit_distance(left, right)
        previous = (0..right.length).to_a
        left.each_char.with_index(1) do |left_character, row|
          current = [row]
          right.each_char.with_index(1) do |right_character, column|
            current[column] = [
              current[column - 1] + 1,
              previous[column] + 1,
              previous[column - 1] + (left_character == right_character ? 0 : 1)
            ].min
          end
          previous = current
        end
        previous.last
      end

      # @rbs (Integer state) -> untyped
      def default_action(state)
        parser_tables.fetch(:default_actions, EMPTY_ROW)[state]
      end

      # @rbs (Hash[Symbol, untyped] tables) -> bool
      def track_locations?(tables)
        tables.fetch(:uses_locations, false) || !@runtime_observers.nil?
      end

      # Keep allocation out of the ordinary two-element lexer path. If a
      # location first appears after values have already shifted, backfill the
      # parallel prefix with nil exactly once.
      # @rbs (untyped location) -> void
      def push_location(location)
        stack = @location_stack
        if stack
          stack << location
        elsif location
          new_stack = Array.new(@value_stack.length)
          new_stack << location
          @location_stack = new_stack
        end
      end

      # @rbs (Integer length) -> Array[untyped]
      def pop_reduction_locations(length)
        stack = @location_stack
        return Array.new(length) unless stack

        locations = stack.last(length)
        stack.pop(length)
        locations
      end

      # @rbs (untyped table, Integer row, Integer column) -> untyped
      def table_lookup(table, row, column)
        return table.lookup(row, column) if table.respond_to?(:lookup)

        table.fetch(row, EMPTY_ROW)[column]
      end

      # @rbs (String message) -> void
      def trace(message)
        @yydebug_output.puts("ibex: #{message}") if @yydebug
      end

      # @rbs (untyped value, Integer symbol_id) -> String
      def trace_value_suffix(value, symbol_id)
        return "" unless @yydebug

        printer = @trace_value_printer
        rendered = if printer
                     printer.call(value)
                   else
                     method_name = parser_tables.fetch(:value_printers, EMPTY_ROW)[symbol_id]
                     return "" unless method_name

                     __send__(method_name, value)
                   end
        " value=#{rendered}"
      rescue StandardError => e
        " value=<printer error: #{e.class}>"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
