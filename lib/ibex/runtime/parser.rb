# frozen_string_literal: true
# rbs_inline: enabled

require_relative "location_span" unless defined?(Ibex::Runtime::LocationSpan)
require_relative "observation" unless defined?(Ibex::Runtime::Observation)
require_relative "resource_limits" unless defined?(Ibex::Runtime::ResourceLimits)
require_relative "repair" unless defined?(Ibex::Runtime::RepairPolicy)
require_relative "repair_search" unless defined?(Ibex::Runtime::RepairSearch)
require_relative "parser_sync_recovery" unless defined?(Ibex::Runtime::ParserSyncRecovery)
require_relative "table_format" unless defined?(Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION)

module Ibex
  module Runtime
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
    # Format-v2 and newer generated production entries mark their five-argument
    # semantic methods with `location_action: true`. Format-v3 and newer
    # composed actions additionally use `composition_action: true` for the
    # six-argument contract carrying the lookahead location. Format-v4
    # location-free generated methods use `values_action: true` for a
    # one-argument values contract. Format-v5 additionally marks proven-safe
    # zero-to-four-value methods with `positional_action: true`. V1 and
    # unmarked application actions retain the historical two-argument
    # contract. Markers are honored only for the generated `_ibex_action_N`
    # Symbol shape, never for callables.
    class Parser
      # Keep direct singleton-hook mutation visible even when an application
      # replaces Ruby's mutation callbacks without calling super.
      module FastPathMutationTracker
        # @rbs (Ibex::Runtime::Parser parser, UnboundMethod lookup) -> bool
        def self.effective_for?(parser, lookup)
          added = lookup.bind_call(parser, :singleton_method_added) # @type var added: Method
          removed = lookup.bind_call(parser, :singleton_method_removed) # @type var removed: Method
          undefined = lookup.bind_call(parser, :singleton_method_undefined) # @type var undefined: Method
          added.owner.equal?(self) && removed.owner.equal?(self) && undefined.owner.equal?(self)
        rescue NameError
          false
        end

        private

        # @rbs (Symbol name) -> void
        def singleton_method_added(name)
          case name
          when :on_shift, :on_shift_location, :on_reduce, :on_reduce_location, :token_to_str
            @runtime_fast_path = false
            @runtime_fast_path_hooks_mutated = true
          end
          super
        end

        # @rbs (Symbol name) -> void
        def singleton_method_removed(name)
          case name
          when :on_shift, :on_shift_location, :on_reduce, :on_reduce_location, :token_to_str
            @runtime_fast_path = false
            @runtime_fast_path_hooks_mutated = true
          end
          super
        end

        # @rbs (Symbol name) -> void
        def singleton_method_undefined(name)
          case name
          when :on_shift, :on_shift_location, :on_reduce, :on_reduce_location, :token_to_str
            @runtime_fast_path = false
            @runtime_fast_path_hooks_mutated = true
          end
          super
        end
      end

      # Invalidates the generated-class hook cache when the parser class
      # changes its own effective hook surface.
      module FastPathClassMutationTracker
        # @rbs (Symbol name) -> void
        def method_added(name)
          __ibex_invalidate_fast_path_hooks(name)
          super
        end

        # @rbs (Symbol name) -> void
        def method_removed(name)
          __ibex_invalidate_fast_path_hooks(name)
          super
        end

        # @rbs (Symbol name) -> void
        def method_undefined(name)
          __ibex_invalidate_fast_path_hooks(name)
          super
        end

        # @rbs (*Module modules) -> self
        def include(*modules)
          __ibex_bump_fast_path_hook_version
          super
        end

        # @rbs (*Module modules) -> self
        def prepend(*modules)
          __ibex_bump_fast_path_hook_version
          super
        end

        private

        # @rbs (Symbol name) -> void
        def __ibex_invalidate_fast_path_hooks(name)
          __ibex_bump_fast_path_hook_version if FAST_PATH_HOOK_NAMES.include?(name)
        end

        # @rbs () -> void
        def __ibex_bump_fast_path_hook_version
          current = instance_variable_get(:@__ibex_fast_path_hook_version) || 0
          instance_variable_set(:@__ibex_fast_path_hook_version, current + 1)
          remove_instance_variable(:@__ibex_fast_path_hook_cache) if
            instance_variable_defined?(:@__ibex_fast_path_hook_cache)
        end

        private :method_added, :method_removed, :method_undefined
      end

      include Observation
      include ParserSyncRecovery

      ParseError = Ibex::Runtime::ParseError #: singleton(Ibex::Runtime::ParseError)
      EOF_TOKEN = 0 #: Integer
      ERROR_TOKEN = 1 #: Integer
      GENERATED_ACTION_NAME = /\A_ibex_action_\d+\z/ #: Regexp
      NO_LOOKAHEAD = Object.new.freeze #: Object
      RECOVERY_SHIFTS = 3 #: Integer
      FAST_PATH_HOOK_NAMES = %i[
        on_shift on_shift_location on_reduce on_reduce_location token_to_str
      ].freeze #: Array[Symbol]
      FAST_PATH_HOOK_REFERENCES = {
        on_shift: :__ibex_fast_path_on_shift,
        on_shift_location: :__ibex_fast_path_on_shift_location,
        on_reduce: :__ibex_fast_path_on_reduce,
        on_reduce_location: :__ibex_fast_path_on_reduce_location,
        token_to_str: :__ibex_fast_path_token_to_str
      }.freeze #: Hash[Symbol, Symbol]
      ERROR_ACTION = [:error].freeze #: [:error]
      SYNC_RECOVER_ACTION = [:sync_recover].freeze #: [:sync_recover]
      CONTINUE_OUTCOME = [:continue].freeze #: [:continue]
      REPAIR_PENDING_OUTCOME = [:repair_pending].freeze #: [:repair_pending]
      TERMINAL_OUTCOMES = %i[accepted done].freeze #: Array[Symbol]
      COMPACT_ACCEPTED = Object.new.freeze #: Object
      empty_row = {} # @type var empty_row: Hash[Integer, untyped]
      empty_location_names = {} # @type var empty_location_names: Hash[Symbol, Integer]
      empty_locations = [] # @type var empty_locations: Array[untyped]

      EMPTY_ROW = empty_row.freeze #: Hash[Integer, untyped]
      EMPTY_LOCATION_NAMES = empty_location_names.freeze #: Hash[Symbol, Integer]
      EMPTY_LOCATIONS = empty_locations.freeze #: Array[untyped]
      private_constant :ERROR_ACTION, :SYNC_RECOVER_ACTION, :CONTINUE_OUTCOME, :REPAIR_PENDING_OUTCOME,
                       :TERMINAL_OUTCOMES, :COMPACT_ACCEPTED, :FAST_PATH_HOOK_NAMES, :FAST_PATH_HOOK_REFERENCES,
                       :FastPathMutationTracker, :FastPathClassMutationTracker

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
      # @rbs @green_builder: CST::GreenBuilder?
      # @rbs @green_kinds: CST::Kind?
      # @rbs @green_cache: CST::NodeCache?
      # @rbs @syntax_root: CST::SyntaxNode?
      # @rbs @syntax_diagnostics: Array[untyped]
      # @rbs @green_pending_skipped: Array[CST::GreenTrivia]
      # @rbs @resource_limits: ResourceLimits
      # @rbs @recovery_attempts: Integer
      # @rbs @runtime_parser_tables: Hash[Symbol, untyped]?
      # @rbs @runtime_fast_path: bool
      # @rbs @runtime_fast_path_tracker_installed: bool
      # @rbs @runtime_fast_path_hooks_mutated: bool
      # @rbs @runtime_fast_path_singleton_ancestors: Array[Module]?
      # @rbs @syntax_only: bool
      # @rbs @green_cache_override: CST::NodeCache?
      # @rbs @green_token_states: Array[Symbol]

      # Start a syntax-only incremental session backed by a generated lexer.
      # @rbs (CST::SourceText source_text, ?resource_limits: ResourceLimits?) -> CST::IncrementalParseSession
      def self.incremental_session(source_text, resource_limits: nil)
        CST::IncrementalParseSession.new(self, source_text, resource_limits: resource_limits)
      end

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
        @runtime_fast_path = false
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
        drive_parser(nil)
      end

      # Parse through `next_token` and return both the semantic value and Red root.
      # @rbs () -> CST::ParseResult
      def parse_with_syntax
        syntax_parse_result(do_parse)
      end

      # Return the Red source-file root built by the most recent CST parse.
      # @rbs () -> CST::SyntaxNode?
      def syntax_root
        ensure_runtime_initialized!
        @syntax_root
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
          refresh_runtime_fast_path_after_user_code!
          if @repair_policy
            enqueue_or_assign_repair_input(repair_input(token, value, location))
          else
            @lookahead = internal_token_id(token)
            @lookahead_value = value
            @lookahead_location = location
            @runtime_fast_path = false unless nil.equal?(location)
            materialize_compatible_lookahead
          end
          run_push_lookahead
        end
      end

      # Supply EOF to a caller-driven parser session and return its result.
      # @rbs (?location: untyped) -> untyped
      def finish(location: nil)
        run_push_driver do
          start_push_session
          refresh_runtime_fast_path_after_user_code!
          if @repair_policy
            enqueue_or_assign_repair_input(
              RepairInput.new(token_id: EOF_TOKEN, token_name: token_to_str(EOF_TOKEN), value: nil, location: location)
            )
          else
            @lookahead = EOF_TOKEN
            @lookahead_value = nil
            @lookahead_location = location
            @runtime_fast_path = false unless nil.equal?(location)
            materialize_compatible_lookahead
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
          @runtime_parser_tables = nil
          @runtime_fast_path = false
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
        @runtime_fast_path = false
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
        @runtime_fast_path = false
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

      alias __ibex_fast_path_on_shift on_shift
      alias __ibex_fast_path_on_shift_location on_shift_location
      alias __ibex_fast_path_on_reduce on_reduce
      alias __ibex_fast_path_on_reduce_location on_reduce_location
      alias __ibex_fast_path_token_to_str token_to_str

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
        @green_builder = nil unless preserve_existing && defined?(@green_builder)
        @green_kinds = nil unless preserve_existing && defined?(@green_kinds)
        @green_cache = nil unless preserve_existing && defined?(@green_cache)
        @syntax_root = nil unless preserve_existing && defined?(@syntax_root)
        @syntax_diagnostics = [] unless preserve_existing && defined?(@syntax_diagnostics)
        @green_pending_skipped = [] unless preserve_existing && defined?(@green_pending_skipped)
        @recovery_attempts = 0 unless preserve_existing && defined?(@recovery_attempts)
        @runtime_parser_tables = nil unless preserve_existing && defined?(@runtime_parser_tables)
        @runtime_fast_path = false unless preserve_existing && defined?(@runtime_fast_path)
        @runtime_fast_path_tracker_installed = false unless
          preserve_existing && defined?(@runtime_fast_path_tracker_installed)
        @runtime_fast_path_hooks_mutated = false unless
          preserve_existing && defined?(@runtime_fast_path_hooks_mutated)
        @runtime_fast_path_singleton_ancestors = nil unless
          preserve_existing && defined?(@runtime_fast_path_singleton_ancestors)
        @syntax_only = false unless preserve_existing && defined?(@syntax_only)
        @green_cache_override = nil unless preserve_existing && defined?(@green_cache_override)
        @green_token_states = [] unless preserve_existing && defined?(@green_token_states)
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

        if length.is_a?(Integer)
          if length.negative?
            stack.pop(length)
            return false
          end

          remaining = length
          while remaining.positive?
            stack.pop
            remaining -= 1
          end
        else
          stack.pop(length)
        end
        target = table_lookup(parser_tables.fetch(:gotos), stack.last, production.fetch(:lhs))
        return false unless target

        stack << target
        true
      end

      # @rbs ((^() -> untyped)? source, ?initial_state: Integer?) -> untyped
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
          tables = @runtime_parser_tables
          if tables && compact_fast_driver_eligible?(tables)
            fast_outcome = drive_compact_fast_parser(tables)
            return @value_stack.last if fast_outcome.equal?(COMPACT_ACCEPTED)
            return fast_outcome.fetch(1) if fast_outcome.is_a?(Array) &&
                                            TERMINAL_OUTCOMES.include?(fast_outcome[0])
          end
          loop do
            outcome = perform(action_for_current_state)
            case outcome[0]
            when :accepted, :done then return outcome[1]
            end
          end
        ensure
          @source = nil
          @runtime_parser_tables = nil
          @runtime_fast_path = false
          release_driver
        end
      end

      # Generated compact tables can keep the unobserved, location-free pull
      # loop on their frozen displacement arrays. Any extension boundary or
      # exceptional table shape returns control to the generic driver without
      # replaying a committed action.
      # rubocop:disable Metrics/AbcSize, Metrics/BlockNesting, Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
      # Direct comparisons avoid predicate-method dispatch inside the parser loop.
      # rubocop:disable Style/BitwisePredicate, Style/NumericPredicate
      # @rbs (Hash[Symbol, untyped] tables) -> (Object | [:accepted, untyped] | [:done, untyped])?
      def drive_compact_fast_parser(tables)
        actions = tables.fetch(:actions)
        gotos = tables.fetch(:gotos)
        productions = tables.fetch(:productions)
        default_codes = tables.fetch(:compact_default_actions)
        token_ids = tables.fetch(:tokens)
        dense_action_codes = actions.dense_codes
        action_column_count = actions.column_count
        dense_goto_values = gotos.dense_values
        goto_dense_width = gotos.dense_width
        return unless dense_action_codes && action_column_count &&
                      dense_goto_values && goto_dense_width &&
                      (tables[:compact_action_encoding] == :signed || default_codes.empty?)

        production_lhs_ids = productions.lhs_ids
        production_lengths = productions.lengths
        production_actions = productions.actions
        production_flags = productions.flags
        borrowed_values_flag = Ibex::Tables::CompactProductions::BORROWED_VALUES_ACTION
        positional_action_flag = Ibex::Tables::CompactProductions::POSITIONAL_ACTION
        states = @state_stack
        values = @value_stack
        stack_limit = @resource_limits.max_stack_depth
        accept_code = Ibex::Tables::CompactActions::ACCEPT_CODE
        error_code = Ibex::Tables::CompactActions::ERROR_CODE
        shift_base = Ibex::Tables::CompactActions::SHIFT_BASE
        reduce_base = Ibex::Tables::CompactActions::REDUCE_BASE

        while @runtime_fast_path
          if @lookahead.equal?(NO_LOOKAHEAD)
            source = @source

            token = begin
              source ? source.call : next_token
            rescue StopIteration
              false
            end
            @runtime_fast_path = false if
              @yydebug || @runtime_observers || @repair_policy || @location_stack ||
              @semantic_error || @accept_requested
            if token.nil? || token == false
              @lookahead = EOF_TOKEN
              @lookahead_value = nil
              @lookahead_location = nil
            else
              external_token, @lookahead_value, @lookahead_location = token
              if external_token.nil? || external_token == false
                @lookahead = EOF_TOKEN
              else
                token_id = token_ids[external_token]
                if token_id
                  @lookahead = token_id
                else
                  @unknown_token_name = external_token.inspect
                  @unknown_token_id = -external_token.object_id.abs
                  @lookahead = @unknown_token_id
                end
              end
            end
            @runtime_fast_path = false unless nil.equal?(@lookahead_location)
            unless @runtime_fast_path
              materialize_compatible_lookahead
              return
            end
          end
          return if @unknown_token_id == @lookahead

          state = states[-1]
          code = dense_action_codes[(state * action_column_count) + @lookahead] ||
                 default_codes[state]
          return unless code

          if code == accept_code
            return COMPACT_ACCEPTED
          elsif code == error_code
            return
          elsif code > 0
            ensure_stack_capacity! if states.length >= stack_limit
            states << (code - shift_base)
            values << @lookahead_value
            @lookahead = NO_LOOKAHEAD
            @lookahead_location = nil
            @runtime_lookahead_token_display = nil
          else
            production_id = reduce_base - code
            lhs = production_lhs_ids[production_id]
            length = production_lengths[production_id]
            return unless length <= values.length && length < states.length

            semantic_action = production_actions[production_id]
            if !semantic_action && length == 1
              goto_row = states[-2]
              next_state = dense_goto_values[(goto_row * goto_dense_width) + lhs]
              raise ParseError, "(tables):1:1: missing goto for production #{production_id}" if next_state.nil?

              states[-1] = next_state
              next
            end
            hook_values = EMPTY_LOCATIONS
            if semantic_action
              flags = production_flags[production_id]
              positional_action = (flags & positional_action_flag) != 0
              if positional_action
                case length
                when 1
                  value0 = values[-1]
                when 2
                  value0 = values[-2]
                  value1 = values[-1]
                when 3
                  value0 = values[-3]
                  value1 = values[-2]
                  value2 = values[-1]
                when 4
                  value0 = values[-4]
                  value1 = values[-3]
                  value2 = values[-2]
                  value3 = values[-1]
                end
              else
                reduction_values = values.last(length)
                hook_values = if (flags & borrowed_values_flag) == 0
                                reduction_values.dup
                              else
                                reduction_values
                              end
              end
            else
              positional_action = false
              result = length.zero? ? nil : values[-length]
            end

            case length
            when 0
              nil
            when 1
              states.pop
              values.pop
            when 2
              states.pop
              states.pop
              values.pop
              values.pop
            when 3
              states.pop
              states.pop
              states.pop
              values.pop
              values.pop
              values.pop
            when 4
              states.pop
              states.pop
              states.pop
              states.pop
              values.pop
              values.pop
              values.pop
              values.pop
            else
              remaining = length
              while remaining > 0
                states.pop
                values.pop
                remaining -= 1
              end
            end

            if semantic_action
              previous_locations = @semantic_locations
              previous_names = @semantic_location_names
              previous_result_location = @semantic_result_location
              @semantic_locations = EMPTY_LOCATIONS
              @semantic_location_names = EMPTY_LOCATION_NAMES
              @semantic_result_location = nil
              begin
                result = if positional_action
                           case length
                           when 0 then __send__(semantic_action)
                           when 1 then __send__(semantic_action, value0)
                           when 2 then __send__(semantic_action, value0, value1)
                           when 3 then __send__(semantic_action, value0, value1, value2)
                           when 4 then __send__(semantic_action, value0, value1, value2, value3)
                           end
                         else
                           __send__(semantic_action, reduction_values)
                         end
              ensure
                @semantic_locations = previous_locations
                @semantic_location_names = previous_names
                @semantic_result_location = previous_result_location
              end
              @runtime_fast_path = false if
                @yydebug || @runtime_observers || @repair_policy || @location_stack ||
                @semantic_error || @accept_requested
            end

            goto_row = states[-1]
            next_state = dense_goto_values[(goto_row * goto_dense_width) + lhs]
            raise ParseError, "(tables):1:1: missing goto for production #{production_id}" if next_state.nil?

            ensure_stack_capacity! if states.length >= stack_limit
            states << next_state
            location_stack = @location_stack
            location_stack << nil if location_stack
            values << result
            if semantic_action
              trace_reduction(production_id, length, lhs, result, next_state) if @yydebug
              unless @runtime_fast_path
                if positional_action
                  case length
                  when 0 then hook_values = EMPTY_LOCATIONS
                  when 1 then hook_values = [value0]
                  when 2 then hook_values = [value0, value1]
                  when 3 then hook_values = [value0, value1, value2]
                  when 4 then hook_values = [value0, value1, value2, value3]
                  end
                end
                lookup = Object.instance_method(:method)
                unless runtime_method_unchanged?(lookup, :on_reduce, :__ibex_fast_path_on_reduce)
                  on_reduce(production_id, hook_values, result)
                end
                unless runtime_method_unchanged?(lookup, :on_reduce_location, :__ibex_fast_path_on_reduce_location)
                  on_reduce_location(production_id, hook_values, result, Array.new(length), nil)
                end
              end
              return accept_reduction(result) if @accept_requested
              return recover(report: false) if @semantic_error

              next
            end
          end
        end
        nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/BlockNesting, Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity
      # rubocop:enable Style/BitwisePredicate, Style/NumericPredicate

      # @rbs (Hash[Symbol, untyped]? tables) -> bool
      def compact_fast_driver_eligible?(tables)
        return false unless @runtime_fast_path && tables
        return false unless tables[:compact_fast_driver] == true
        return false unless tables.fetch(:eager_reductions, EMPTY_ROW).empty?
        return false unless defined?(Ibex::Tables::Compact)

        tables.fetch(:actions).instance_of?(Ibex::Tables::CompactActions) &&
          tables.fetch(:gotos).instance_of?(Ibex::Tables::Compact) &&
          tables.fetch(:productions).instance_of?(Ibex::Tables::CompactProductions) &&
          tables.fetch(:productions).direct_values?
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
        @runtime_parser_tables = nil
        @runtime_fast_path = false
        clear_sync_recovery
      end

      # @rbs ((^() -> untyped)? source, ?initial_state: Integer?) -> void
      def prepare_parse(source, initial_state: nil)
        @runtime_parser_tables = load_parser_tables
        tables = validate_parser_table_format!
        initial_state = resolve_initial_state(tables, initial_state)

        @source = source
        @state_stack.clear << initial_state
        @value_stack.clear
        initialize_runtime_fast_path(tables)
        @lookahead = NO_LOOKAHEAD
        @lookahead_value = nil
        @lookahead_location = nil
        @runtime_lookahead_token_display = nil
        reset_parse_recovery_state
        @accept_requested = false
        @unknown_token_id = nil
        reset_cst_results(tables)
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

        if actual >= 3 && !generated_action_contracts_validated?(tables)
          validate_generated_action_contracts!(tables, actual)
          cache_generated_action_contracts!(tables)
        end
        tables
      end

      # Generated parser tables are deeply frozen before they can cross a
      # Ractor boundary. Their action-marker contract only needs one scan per
      # parser class and exact table object, including across parser instances.
      # Mutable application tables remain intentionally uncached.
      # @rbs (Hash[Symbol, untyped] tables) -> bool
      def generated_action_contracts_validated?(tables)
        return false unless generated_action_contract_cache_accessible?

        cached = self.class.instance_variable_get(:@__ibex_validated_parser_tables)
        cached.equal?(tables)
      end

      # @rbs (Hash[Symbol, untyped] tables) -> void
      def cache_generated_action_contracts!(tables)
        shareable = defined?(Ractor) && Ractor.respond_to?(:shareable?) && Ractor.shareable?(tables)
        return unless shareable
        return unless generated_action_contract_cache_accessible?

        self.class.instance_variable_set(:@__ibex_validated_parser_tables, tables)
      rescue FrozenError
        nil
      end

      # Ruby 3.0-3.3 expose the main Ractor as an object instead of exposing
      # Ractor.main?. Class instance variables cannot be read or written from
      # another Ractor on those versions.
      # @rbs () -> bool
      def generated_action_contract_cache_accessible?
        return true unless Object.const_defined?(:Ractor, false)

        ractor = Object.const_get(:Ractor)
        return ractor.__send__(:main?) if ractor.respond_to?(:main?)
        return ractor.__send__(:current).equal?(ractor.__send__(:main)) if
          ractor.respond_to?(:current) && ractor.respond_to?(:main)

        true
      end

      # @rbs (Hash[Symbol, untyped] tables, Integer version) -> void
      def validate_generated_action_contracts!(tables, version)
        tables.fetch(:productions).each_with_index do |production, index|
          validate_composition_action_contract!(production, index, version)
          validate_values_action_contract!(production, index, version)
          validate_positional_action_contract!(production, index, version)
        end
      end

      # @rbs (Hash[Symbol, untyped] production, Integer index, Integer version) -> void
      def validate_composition_action_contract!(production, index, version)
        return unless production[:composition_action] == true
        return if production[:location_action] == true && generated_action_symbol?(production[:action])

        raise ParseError,
              "(tables):1:1: parser table format version #{version} production #{index} has an inconsistent " \
              ":composition_action marker; a generated action Symbol with :location_action is required"
      end

      # @rbs (Hash[Symbol, untyped] production, Integer index, Integer version) -> void
      def validate_values_action_contract!(production, index, version)
        borrowed = production[:borrowed_values_action] == true
        if borrowed && production[:values_action] != true
          raise ParseError,
                "(tables):1:1: parser table format version #{version} production #{index} has an inconsistent " \
                ":borrowed_values_action marker; :values_action is required"
        end
        return if version < 4 || production[:values_action] != true
        return if generated_action_symbol?(production[:action]) &&
                  production[:location_action] != true &&
                  production[:composition_action] != true &&
                  production.fetch(:location_context_length, 0).zero?

        raise ParseError,
              "(tables):1:1: parser table format version #{version} production #{index} has an inconsistent " \
              ":values_action marker; a generated action Symbol without location, composition, or context " \
              "markers is required"
      end

      # @rbs (Hash[Symbol, untyped] production, Integer index, Integer version) -> void
      def validate_positional_action_contract!(production, index, version)
        return if version < 5 || production[:positional_action] != true

        return if positional_action_contract?(production)

        raise ParseError,
              "(tables):1:1: parser table format version #{version} production #{index} has an inconsistent " \
              ":positional_action marker; a generated action Symbol with zero to four RHS values and no other " \
              "action ABI markers is required"
      end

      # @rbs (Hash[Symbol, untyped] production) -> bool
      def positional_action_contract?(production)
        production[:length].is_a?(Integer) &&
          production[:length].between?(0, 4) &&
          generated_action_symbol?(production[:action]) &&
          production[:values_action] != true &&
          production[:borrowed_values_action] != true &&
          production[:location_action] != true &&
          production[:composition_action] != true &&
          production.fetch(:location_context_length, 0).zero?
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
        when :shift
          next_state = action.fetch(1)
          @runtime_fast_path ? fast_shift(next_state) : shift(next_state)
        when :reduce
          production_id = action.fetch(1)
          if @runtime_fast_path
            production = parser_tables.fetch(:productions).fetch(production_id)
            length = production.fetch(:length)
            return fast_reduce(production_id, production, length) if fast_reduction_eligible?(production, length)
          end

          reduce(production_id, production)
        when :accept
          result = finalize_cst(@value_stack.last)
          emit_accept_event(EventSanitizer.value(result), "table") if @runtime_observers
          [:accepted, result]
        when :error
          materialize_lookahead_token_display!
          recover
        when :sync_recover
          materialize_lookahead_token_display!
          continue_sync_recovery
        else raise ParseError, "(tables):1:1: unknown parser action #{action.inspect}"
        end
      end

      # @rbs (Integer next_state) -> [:continue]
      def fast_shift(next_state)
        value = @lookahead_value
        ensure_stack_capacity!
        @state_stack << next_state
        @value_stack << value
        @lookahead = NO_LOOKAHEAD
        @lookahead_location = nil
        @runtime_lookahead_token_display = nil
        @recovery_shifts -= 1 if @recovery_shifts.positive?
        CONTINUE_OUTCOME
      end

      # @rbs (Hash[Symbol, untyped] production, untyped length) -> bool
      def fast_reduction_eligible?(production, length)
        action = production[:action]
        return false if action && !generated_values_action?(production, action)

        length.is_a?(Integer) && !length.negative? &&
          length <= @value_stack.length && length < @state_stack.length
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Integer length) -> [:continue]
      def fast_reduce(production_id, production, length)
        action = production[:action]
        return fast_values_reduce(production_id, production, length, action) if action

        result = length.zero? ? nil : @value_stack.fetch(@value_stack.length - length)
        remaining = length
        while remaining.positive?
          @state_stack.pop
          @value_stack.pop
          remaining -= 1
        end
        next_state = table_lookup(parser_tables.fetch(:gotos), @state_stack.last, production.fetch(:lhs))
        raise ParseError, "(tables):1:1: missing goto for production #{production_id}" if next_state.nil?

        ensure_stack_capacity!
        @state_stack << next_state
        @value_stack << result
        CONTINUE_OUTCOME
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Integer length, Symbol action) -> untyped
      def fast_values_reduce(production_id, production, length, action)
        hook_values = @value_stack.last(length)
        values = hook_values.dup
        remaining = length
        while remaining.positive?
          @state_stack.pop
          @value_stack.pop
          remaining -= 1
        end
        result = values_reduction_value(production, action, values, EMPTY_LOCATIONS, nil)
        refresh_runtime_fast_path_after_user_code!
        next_state = table_lookup(parser_tables.fetch(:gotos), @state_stack.last, production.fetch(:lhs))
        raise ParseError, "(tables):1:1: missing goto for production #{production_id}" if next_state.nil?

        ensure_stack_capacity!
        push_reduction_result(next_state, result, nil)
        trace_reduction(production_id, length, production.fetch(:lhs), result, next_state)
        unless @runtime_fast_path
          lookup = Object.instance_method(:method)
          unless runtime_method_unchanged?(lookup, :on_reduce, :__ibex_fast_path_on_reduce)
            on_reduce(production_id, hook_values, result)
          end
          unless runtime_method_unchanged?(lookup, :on_reduce_location, :__ibex_fast_path_on_reduce_location)
            on_reduce_location(production_id, hook_values, result, Array.new(length), nil)
          end
        end
        return accept_reduction(result) if @accept_requested
        return recover(report: false) if @semantic_error

        CONTINUE_OUTCOME
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
        shift_green_token(token_id, value, location)
        @lookahead = NO_LOOKAHEAD
        @lookahead_location = nil
        @runtime_lookahead_token_display = nil
        @recovery_shifts -= 1 if @recovery_shifts.positive?
        on_shift(token_id, value, next_state)
        on_shift_location(token_id, value, next_state, location)
        emit_runtime_event(:shift, event_data, observers: event_observers) if event_data
        CONTINUE_OUTCOME
      end

      # @rbs (Integer production_id, ?Hash[Symbol, untyped]? prefetched_production) -> untyped
      def reduce(production_id, prefetched_production = nil) # rubocop:disable Metrics -- allocation-free hot path.
        production = prefetched_production || parser_tables.fetch(:productions).fetch(production_id)
        length = production.fetch(:length)
        event_observers = runtime_observer_snapshot if @runtime_observers
        pre_state = @state_stack.last if event_observers
        values = @value_stack.last(length)
        locations = pop_reduction_locations(length)
        hook_values = values.dup
        # Array#last above preserves the native negative-length exception before either stack mutates.
        if length.is_a?(Integer) && !length.negative? &&
           length <= @value_stack.length && length < @state_stack.length
          remaining = length
          while remaining.positive?
            @state_stack.pop
            @value_stack.pop
            remaining -= 1
          end
        else
          @state_stack.pop(length)
          @value_stack.pop(length)
        end
        post_state = @state_stack.last if event_observers
        location = LocationSpan.for_reduction(locations, lookahead: @lookahead_location)
        result = reduction_value(production_id, production, values, locations, location)
        refresh_runtime_fast_path_after_user_code!
        reduce_green(production_id, production, length)
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
      def reduction_value(production_id, production, values, locations, location) # rubocop:disable Metrics -- explicit hot path.
        previous_locations = @semantic_locations
        previous_names = @semantic_location_names
        previous_result_location = @semantic_result_location
        return values.first if @syntax_only

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
        return __send__(action, *values) if generated_positional_action?(production, action)
        return __send__(action, values) if generated_values_action?(production, action)

        value_stack = @value_stack.dup
        callable = action.respond_to?(:call)
        if generated_location_action?(production, action)
          location_stack = (@location_stack || []).dup
          if generated_composition_action?(production, action)
            if callable
              return instance_exec(
                values, value_stack, locations, location_stack, location, @lookahead_location, &action
              )
            end

            return __send__(action, values, value_stack, locations, location_stack, location, @lookahead_location)
          end

          return instance_exec(values, value_stack, locations, location_stack, location, &action) if callable

          return __send__(action, values, value_stack, locations, location_stack, location)
        end

        callable ? instance_exec(values, value_stack, &action) : __send__(action, values, value_stack)
      ensure
        @semantic_locations = previous_locations
        @semantic_location_names = previous_names
        @semantic_result_location = previous_result_location
      end

      # @rbs (Hash[Symbol, untyped] production, Symbol action, Array[untyped] values,
      #   Array[untyped] locations, LocationSpan? location) -> untyped
      def values_reduction_value(production, action, values, locations, location)
        previous_locations = @semantic_locations
        previous_names = @semantic_location_names
        previous_result_location = @semantic_result_location
        @semantic_locations = locations
        @semantic_location_names = production.fetch(:location_names, EMPTY_LOCATION_NAMES)
        @semantic_result_location = location
        __send__(action, values)
      ensure
        @semantic_locations = previous_locations
        @semantic_location_names = previous_names
        @semantic_result_location = previous_result_location
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Array[untyped] values,
      #   Array[untyped] locations, LocationSpan? location) -> untyped
      def actionless_reduction_value(production_id, production, values, locations, location)
        return values.first unless cst_enabled? && !red_green_cst?

        cst_reduction_value(production_id, production, values, locations, location)
      end

      # @rbs (Hash[Symbol, untyped] production, untyped action) -> bool
      def generated_location_action?(production, action)
        parser_tables.fetch(:format_version) >= 2 &&
          production[:location_action] == true &&
          generated_action_symbol?(action)
      end

      # @rbs (Hash[Symbol, untyped] production, untyped action) -> bool
      def generated_values_action?(production, action)
        parser_tables.fetch(:format_version) >= 4 &&
          production[:values_action] == true &&
          generated_action_symbol?(action)
      end

      # @rbs (Hash[Symbol, untyped] production, untyped action) -> bool
      def generated_positional_action?(production, action)
        parser_tables.fetch(:format_version) >= 5 &&
          production[:positional_action] == true &&
          generated_action_symbol?(action)
      end

      # @rbs (Hash[Symbol, untyped] production, untyped action) -> bool
      def generated_composition_action?(production, action)
        parser_tables.fetch(:format_version) >= 3 &&
          production[:composition_action] == true &&
          generated_location_action?(production, action)
      end

      # @rbs (untyped action) -> bool
      def generated_action_symbol?(action)
        action.is_a?(Symbol) && action.name.match?(GENERATED_ACTION_NAME)
      end

      # @rbs () -> bool
      def cst_enabled?
        !parser_tables[:cst].nil? && parser_tables[:cst] != false
      end

      # @rbs () -> bool
      def red_green_cst?
        parser_tables.fetch(:format_version) >= 6 && parser_tables[:cst].is_a?(Hash)
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

        if red_green_cst?
          @syntax_diagnostics << {
            token_id: token_id, value: value, location: location, reason: reason
          }.freeze
          return
        end

        @cst_errors << CST::Error.new(
          symbol: token_to_str(token_id), value: value, location: location, reason: reason
        )
      end

      # @rbs (untyped value) -> CST::Node
      def finalize_cst(value)
        return value unless cst_enabled?
        return finalize_red_green_cst(value) if red_green_cst?

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

      # @rbs () -> CST::Node?
      def failed_cst
        if red_green_cst?
          finalize_failed_green_cst
          return nil
        end

        capture_cst_error(@lookahead, @lookahead_value, @lookahead_location, :syntax) if @cst_errors.empty?
        CST::Node.new(
          symbol: parser_tables.fetch(:cst_start), production_id: -1,
          children: @cst_errors.dup, location: @lookahead_location
        )
      end

      # @rbs (ParseError error) -> CST::Node?
      def cst_lexical_failure(error)
        if red_green_cst?
          @syntax_diagnostics << error
          finalize_lexical_green_cst(error)
          return nil
        end

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

      # @rbs (Hash[Symbol, untyped] tables) -> void
      def prepare_green_cst(tables)
        @syntax_root = nil
        @syntax_diagnostics.clear
        @green_pending_skipped.clear
        config = tables[:cst]
        unless config.is_a?(Hash)
          @green_builder = nil
          @green_kinds = nil
          @green_cache = nil
          return
        end

        kinds = CST::Kind.new(config.fetch(:kinds), slots: config.fetch(:slots))
        cache = @green_cache_override || CST::NodeCache.new
        @green_kinds = kinds
        @green_cache = cache
        @green_token_states.clear
        @green_builder = CST::GreenBuilder.new(kinds: kinds, cache: cache)
      end

      # @rbs (Hash[Symbol, untyped] tables) -> void
      def reset_cst_results(tables)
        @cst_errors.clear
        prepare_green_cst(tables)
      end

      # @rbs (Integer token_id, untyped value, untyped location) -> void
      def shift_green_token(token_id, value, location)
        builder = @green_builder
        kinds = @green_kinds
        return unless builder && kinds

        trailing = green_location_trivia(location, :cst_previous_trailing)
        builder.append_trailing_to_last_token(trailing)
        repair = cst_location_value(location, :ibex_repair)
        if repair == :insert
          builder.missing(token_id)
          @green_token_states << green_lexer_state(location)
          return
        end

        leading = @green_pending_skipped + green_location_trivia(location, :leading_trivia)
        flags = @green_pending_skipped.empty? ? 0 : CST::Flags::CONTAINS_SKIPPED
        @green_pending_skipped.clear
        flags |= CST::Flags::CONTAINS_ERROR if repair == :replace || token_id == ERROR_TOKEN
        kind = token_id.negative? ? kinds.fetch(:lexical_error_token) : token_id
        builder.token(kind, green_token_text(value, location), leading: leading, flags: flags)
        @green_token_states << green_lexer_state(location)
      end

      # @rbs (Integer production_id, Hash[Symbol, untyped] production, Integer length) -> void
      def reduce_green(production_id, production, length)
        builder = @green_builder
        return unless builder

        config = parser_tables.fetch(:cst)
        slot = config.fetch(:slots).fetch(production_id, nil)
        kind = slot ? slot.fetch(:node_kind) : production.fetch(:lhs)
        flags = length.zero? ? CST::Flags::SYNTHETIC : 0
        builder.node(kind, length, flags: flags)
      end

      # @rbs (untyped value, untyped location) -> String
      def green_token_text(value, location)
        text = cst_location_value(location, :ibex_cst_text)
        return text if text.is_a?(String)
        return value if value.is_a?(String)

        ""
      end

      # @rbs (untyped location, Symbol key) -> Array[CST::GreenTrivia]
      def green_location_trivia(location, key)
        trivia = cst_location_value(location, key)
        trivia.is_a?(Array) ? trivia.grep(CST::GreenTrivia) : []
      end

      # @rbs (untyped value) -> untyped
      def finalize_red_green_cst(value)
        builder = @green_builder || raise(ParseError, "(cst):1:1: Green builder is unavailable")
        kinds = @green_kinds || raise(ParseError, "(cst):1:1: kind metadata is unavailable")
        incomplete = @lookahead != EOF_TOKEN
        unless incomplete
          builder.append_trailing_to_last_token(green_location_trivia(@lookahead_location, :cst_previous_trailing))
        end
        empty_trivia = [] #: Array[CST::GreenTrivia]
        eof_leading = incomplete ? empty_trivia : green_location_trivia(@lookahead_location, :leading_trivia)
        leading = @green_pending_skipped + eof_leading
        @green_pending_skipped.clear
        eof = builder.make_token(EOF_TOKEN, "", leading: leading)
        @green_token_states << green_lexer_state(@lookahead_location)
        green = if builder.size == 1
                  builder.finish_source_file(eof, incomplete: incomplete)
                else
                  builder.finish_synthetic_root([eof], incomplete: incomplete)
                end
        install_syntax_root(green, kinds)
        value
      end

      # @rbs () -> void
      def finalize_failed_green_cst
        builder = @green_builder || raise(ParseError, "(cst):1:1: Green builder is unavailable")
        kinds = @green_kinds || raise(ParseError, "(cst):1:1: kind metadata is unavailable")
        trailing = [] #: Array[CST::GreenNode | CST::GreenToken]
        builder.append_trailing_to_last_token(green_location_trivia(@lookahead_location, :cst_previous_trailing))
        leading = @green_pending_skipped + green_location_trivia(@lookahead_location, :leading_trivia)
        @green_pending_skipped.clear
        if @lookahead.equal?(NO_LOOKAHEAD)
          trailing << builder.make_token(EOF_TOKEN, "", leading: leading) unless leading.empty?
        elsif @lookahead == EOF_TOKEN
          trailing << builder.make_token(EOF_TOKEN, "", leading: leading)
        else
          kind = @lookahead.is_a?(Integer) && @lookahead >= 0 ? @lookahead : kinds.fetch(:lexical_error_token)
          trailing << builder.make_token(
            kind, green_token_text(@lookahead_value, @lookahead_location),
            leading: leading,
            flags: CST::Flags::CONTAINS_ERROR
          )
        end
        install_syntax_root(builder.finish_synthetic_root(trailing), kinds)
      end

      # @rbs (ParseError error) -> void
      def finalize_lexical_green_cst(error)
        builder = @green_builder || raise(ParseError, "(cst):1:1: Green builder is unavailable")
        kinds = @green_kinds || raise(ParseError, "(cst):1:1: kind metadata is unavailable")
        text = error.token_value.is_a?(String) ? error.token_value : error.token_value.to_s
        token = builder.make_token(
          kinds.fetch(:lexical_error_token), text,
          leading: pending_green_trivia + green_location_trivia(error.location, :leading_trivia),
          flags: CST::Flags::CONTAINS_ERROR
        )
        file = cst_location_value(error.location, :file)
        install_syntax_root(
          builder.finish_synthetic_root([token]), kinds,
          file: file.is_a?(String) ? file : nil
        )
      end

      # @rbs () -> Array[CST::GreenTrivia]
      def pending_green_trivia
        return [] unless respond_to?(:take_cst_pending_green_trivia, true)

        __send__(:take_cst_pending_green_trivia)
      end

      # @rbs (CST::GreenNode green, CST::Kind kinds, ?file: String?) -> void
      def install_syntax_root(green, kinds, file: nil)
        config = parser_tables.fetch(:cst)
        policy = config.fetch(:trivia_policy)
        location_file = cst_location_value(@lookahead_location, :file)
        source_file = file || (location_file if location_file.is_a?(String))
        source = CST::SourceText.new(green.to_source, file: source_file)
        @syntax_root = CST::SyntaxNode.new(
          green: green, kinds: kinds, trivia_policy: policy, source_text: source
        )
        emit_incremental_event(
          :cst_built,
          {
            "descendant_count" => green.descendant_count,
            "full_width" => green.full_width,
            "contains_error" => green.flags.anybits?(CST::Flags::CONTAINS_ERROR)
          }
        )
      end

      # @rbs (untyped value) -> CST::ParseResult
      def syntax_parse_result(value)
        root = @syntax_root
        raise ParseError, "(cst):1:1: parse_with_syntax requires a format-v6 CST parser" unless root

        CST::ParseResult.new(value: value, syntax_root: root, diagnostics: @syntax_diagnostics)
      end

      # @rbs () -> Array[Symbol]
      def syntax_token_states
        @green_token_states.dup.freeze
      end

      # @rbs (untyped location) -> Symbol
      def green_lexer_state(location)
        state = cst_location_value(location, :ibex_lexer_start_state)
        state ? state.to_sym : :INITIAL
      end

      # @rbs (CST::NodeCache cache) { () -> untyped } -> untyped
      def with_syntax_only(cache)
        previous_mode = @syntax_only
        previous_cache = @green_cache_override
        @syntax_only = true
        @green_cache_override = cache
        @runtime_fast_path = false
        yield
      ensure
        @syntax_only = previous_mode
        @green_cache_override = previous_cache
      end

      # @rbs (Symbol type, Hash[untyped, untyped] data) -> void
      def emit_incremental_event(type, data)
        emit_runtime_event(type, data) if @runtime_observers
      end

      # @rbs () -> void
      def discard_green_lookahead
        builder = @green_builder
        kinds = @green_kinds
        return unless builder && kinds

        kind = @lookahead.is_a?(Integer) && @lookahead >= 0 ? @lookahead : kinds.fetch(:lexical_error_token)
        token = builder.make_token(
          kind, green_token_text(@lookahead_value, @lookahead_location),
          leading: green_location_trivia(@lookahead_location, :leading_trivia),
          flags: CST::Flags::CONTAINS_ERROR
        )
        return if builder.append_to_last_error(token)

        @green_pending_skipped << CST::GreenTrivia.new(
          kind: kinds.fetch(:skipped_tokens), text: token.to_source
        )
      end

      # @rbs (?report: bool) -> untyped
      def recover(report: true)
        @runtime_fast_path = false
        materialize_lookahead_token_display! unless @lookahead.equal?(NO_LOOKAHEAD)
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
        discard_green_lookahead
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
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # Green restoration mirrors the existing state/value/location transactional fallback.
      def fallback_recovery(context, token_data, recovery_observers)
        state_stack = @state_stack.dup if sync_recovery_configured?
        value_stack = @value_stack.dup if state_stack
        location_stack = @location_stack&.dup if state_stack
        green_stack = @green_builder&.snapshot if state_stack
        unless shift_error_token
          if state_stack
            @state_stack = state_stack
            install_value_stack(value_stack || [])
            @location_stack = location_stack
            @green_builder&.restore(green_stack || [])
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
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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
        popped = 0
        loop do
          action = table_lookup(parser_tables.fetch(:actions), @state_stack.last, ERROR_TOKEN)
          if action&.first == :shift
            trace("recover: shift error -> state #{action.fetch(1)}") if @yydebug
            ensure_stack_capacity!
            @state_stack << action.fetch(1)
            push_location(@lookahead_location)
            @value_stack << nil
            @green_builder&.absorb_into_error(popped)
            return true
          end
          return false if @state_stack.length == 1

          trace("recover: pop state #{@state_stack.last}") if @yydebug
          @state_stack.pop
          @value_stack.pop
          @location_stack&.pop
          popped += 1
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
        refresh_runtime_fast_path_after_user_code!
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
        @runtime_fast_path = false unless nil.equal?(@lookahead_location)
        materialize_compatible_lookahead
      end

      # @rbs () -> void
      def materialize_compatible_lookahead
        if @runtime_fast_path
          @runtime_lookahead_token_display = nil
        else
          token_display = materialize_lookahead_token_display!
          trace("read #{token_display}") if @yydebug
        end
      end

      # @rbs () -> String
      def materialize_lookahead_token_display!
        token_display = @runtime_lookahead_token_display
        return token_display if token_display

        @runtime_lookahead_token_display = token_to_str(@lookahead)
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
        source ? source.call : next_token
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
        tables = @runtime_parser_tables
        return tables if tables

        load_parser_tables
      end

      # @rbs () -> Hash[Symbol, untyped]
      def load_parser_tables
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

      # @rbs (Hash[Symbol, untyped] tables) -> void
      def initialize_runtime_fast_path(tables)
        @location_stack = track_locations?(tables) ? [] : nil
        @runtime_fast_path = runtime_fast_path_eligible?(tables)
        return unless @runtime_fast_path
        return if @runtime_fast_path_tracker_installed

        install_runtime_fast_path_tracker!
      end

      # @rbs (?Class? singleton) -> void
      def install_runtime_fast_path_tracker!(singleton = nil)
        singleton ||= Object.instance_method(:singleton_class).bind_call(self)
        Module.instance_method(:prepend).bind_call(singleton, FastPathMutationTracker)
        @runtime_fast_path_tracker_installed = true
        @runtime_fast_path_hooks_mutated = false
        @runtime_fast_path_singleton_ancestors = singleton.ancestors.freeze
      rescue FrozenError, TypeError
        @runtime_fast_path = false
      end

      # @rbs () -> void
      def install_runtime_fast_path_class_tracker!
        parser_class = self.class
        return if parser_class.instance_variable_get(:@__ibex_fast_path_class_tracker_installed) == true

        singleton = parser_class.singleton_class
        singleton.prepend(FastPathClassMutationTracker)
        parser_class.instance_variable_set(:@__ibex_fast_path_hook_version, 0)
        parser_class.instance_variable_set(:@__ibex_fast_path_class_tracker_installed, true)
      rescue FrozenError, TypeError
        nil
      end

      # The generic driver remains authoritative whenever a public runtime
      # extension can observe a committed shift or reduction.
      # @rbs (Hash[Symbol, untyped] tables) -> bool
      def runtime_fast_path_eligible?(tables)
        !@syntax_only &&
          !@yydebug &&
          @runtime_observers.nil? &&
          @repair_policy.nil? &&
          tables[:cst] != true &&
          !tables.fetch(:uses_locations, false) &&
          @location_stack.nil? &&
          runtime_fast_path_hooks_eligible?
      end

      # @rbs () -> bool
      def runtime_fast_path_hooks_eligible?
        cached = cached_runtime_fast_path_hooks_eligibility
        return cached unless cached.nil?

        lookup = Object.instance_method(:method)
        hooks_unchanged =
          runtime_method_unchanged?(lookup, :on_shift, :__ibex_fast_path_on_shift) &&
          runtime_method_unchanged?(lookup, :on_shift_location, :__ibex_fast_path_on_shift_location) &&
          runtime_method_unchanged?(lookup, :on_reduce, :__ibex_fast_path_on_reduce) &&
          runtime_method_unchanged?(lookup, :on_reduce_location, :__ibex_fast_path_on_reduce_location) &&
          runtime_method_unchanged?(lookup, :token_to_str, :__ibex_fast_path_token_to_str)
        return false unless hooks_unchanged
        return true unless @runtime_fast_path_tracker_installed

        tracker_effective = FastPathMutationTracker.effective_for?(self, lookup)
        if tracker_effective
          @runtime_fast_path_hooks_mutated = false
          singleton = Object.instance_method(:singleton_class).bind_call(self)
          @runtime_fast_path_singleton_ancestors = singleton.ancestors.freeze
        end
        tracker_effective
      end

      # @rbs () -> bool?
      def cached_runtime_fast_path_hooks_eligibility
        return nil unless @runtime_fast_path_tracker_installed && !@runtime_fast_path_hooks_mutated

        singleton = Object.instance_method(:singleton_class).bind_call(self)
        return false if singleton.frozen?
        return nil unless @runtime_fast_path_singleton_ancestors == singleton.ancestors

        runtime_fast_path_class_hooks_eligible?
      end

      # @rbs () -> bool
      def runtime_fast_path_class_hooks_eligible?
        install_runtime_fast_path_class_tracker!
        parser_class = self.class
        version = parser_class.instance_variable_get(:@__ibex_fast_path_hook_version) || 0
        cached = parser_class.instance_variable_get(:@__ibex_fast_path_hook_cache)
        return cached.fetch(1) if cached.is_a?(Array) && cached[0] == version

        eligible = FAST_PATH_HOOK_REFERENCES.all? do |name, reference|
          runtime_methods_equivalent?(
            parser_class.instance_method(name),
            Parser.instance_method(reference)
          )
        rescue NameError
          false
        end
        parser_class.instance_variable_set(:@__ibex_fast_path_hook_cache, [version, eligible].freeze)
        eligible
      rescue FrozenError, TypeError
        false
      end

      # @rbs (UnboundMethod lookup, Symbol name, Symbol reference) -> bool
      def runtime_method_unchanged?(lookup, name, reference)
        implementation = runtime_core_method(lookup, name)
        expected = runtime_core_method(lookup, reference)
        return false if implementation.nil? || expected.nil?

        runtime_methods_equivalent?(implementation, expected)
      end

      # Ruby 3.0 and 3.1 do not preserve UnboundMethod#== for an inherited
      # method and its alias even though both still identify the same body.
      # @rbs (Method | UnboundMethod implementation, Method | UnboundMethod expected) -> bool
      def runtime_methods_equivalent?(implementation, expected)
        return true if implementation == expected

        implementation.owner.equal?(expected.owner) &&
          implementation.original_name == expected.original_name &&
          implementation.source_location == expected.source_location
      end

      # Bypass an application-defined `method` helper while retaining Ruby's
      # complete singleton/prepend/subclass lookup semantics.
      # @rbs (UnboundMethod lookup, Symbol name) -> Method?
      def runtime_core_method(lookup, name)
        lookup.bind_call(self, name)
      rescue NameError
        nil
      end

      # Re-check after lexer and semantic-action callbacks because those are
      # supported points at which an application can install instrumentation.
      # A disabled fast path never becomes active again within the session.
      # @rbs () -> void
      def refresh_runtime_fast_path_after_user_code!
        return unless @runtime_fast_path

        @runtime_fast_path = false unless
          !@yydebug &&
          @runtime_observers.nil? &&
          @repair_policy.nil? &&
          @location_stack.nil? &&
          @semantic_error == false &&
          @accept_requested == false
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
