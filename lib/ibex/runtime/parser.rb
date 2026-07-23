# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Parser-table shape understood by this runtime.
    PARSER_TABLE_FORMAT_VERSION = 1 #: Integer

    # Raised by the default parser error handler.
    class ParseError < StandardError
      attr_reader :token_id #: Integer?
      attr_reader :token_name #: String?
      attr_reader :token_value #: untyped
      attr_reader :expected_tokens #: Array[String]
      attr_reader :location #: untyped
      attr_reader :state #: Integer?
      attr_reader :suggestions #: Array[String]

      # rubocop:disable Layout/LineLength
      # @rbs (?String? message, ?token_id: Integer?, ?token_name: String?, ?token_value: untyped, ?expected_tokens: Array[String], ?location: untyped, ?state: Integer?, ?suggestions: Array[String], ?detail: String?) -> void
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
        detail: nil
      )
        @token_id = token_id
        @token_name = token_name
        @token_value = token_value
        @expected_tokens = expected_tokens.dup.freeze
        @location = location
        @state = state
        @suggestions = suggestions.dup.freeze
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
        message = "#{location_label}: #{@detail || default}"
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

    # rubocop:disable Metrics/ClassLength

    # Drives a table-defined LR parser without native extensions.
    #
    # Subclasses provide `.parser_tables`, returning `:tokens`, `:token_names`,
    # `:actions`, `:gotos`, and `:productions`, with optional
    # `:default_actions` and `:error_messages`. Actions are represented by
    # `[:shift, state]`, `[:reduce, production]`, `[:accept]`, or `[:error]`.
    class Parser
      EOF_TOKEN = 0 #: Integer
      ERROR_TOKEN = 1 #: Integer
      NO_LOOKAHEAD = Object.new.freeze #: Object
      RECOVERY_SHIFTS = 3 #: Integer
      empty_row = {} # @type var empty_row: Hash[Integer, untyped]

      EMPTY_ROW = empty_row.freeze #: Hash[Integer, untyped]

      # @rbs @yydebug: bool
      # @rbs @yydebug_output: IO
      # @rbs @source: (^() -> untyped)?
      # @rbs @state_stack: Array[Integer]
      # @rbs @value_stack: Array[untyped]
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

      attr_accessor :yydebug #: bool
      attr_writer :yydebug_output #: IO

      # @rbs () -> void
      def initialize
        @yydebug = false
        @yydebug_output = $stderr
        @source = nil
        @state_stack = []
        @value_stack = []
        @lookahead = NO_LOOKAHEAD
        @lookahead_value = nil
        @lookahead_location = nil
        @recovery_shifts = 0
        @semantic_error = false
        @accept_requested = false
        @unknown_token_id = nil
        @push_status = :idle
        @driver_status = :idle
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

        ensure_driver_available!
        run_push_driver do
          start_push_session
          @lookahead = internal_token_id(token)
          @lookahead_value = value
          @lookahead_location = location
          trace("read #{token_to_str(@lookahead)}")
          run_push_lookahead
        end
      end

      # Supply EOF to a caller-driven parser session and return its result.
      # @rbs (?location: untyped) -> untyped
      def finish(location: nil)
        ensure_driver_available!
        run_push_driver do
          start_push_session
          @lookahead = EOF_TOKEN
          @lookahead_value = nil
          @lookahead_location = location
          trace("read #{token_to_str(@lookahead)}")
          outcome = run_push_lookahead
          return outcome.fetch(1) if outcome.is_a?(Array)

          raise ParseError, "(input):1:1: parser requested input after EOF"
        end
      end

      # Discard a caller-driven session so this parser can accept a new one.
      # @rbs () -> nil
      def reset_push
        ensure_driver_available!
        @push_status = :idle
        @source = nil
        @state_stack = []
        @value_stack = []
        @lookahead = NO_LOOKAHEAD
        @lookahead_value = nil
        @lookahead_location = nil
        nil
      end

      # Override in pull parsers. Return `[token, value]`,
      # `[token, value, location]`, `false`, or `nil`.
      # @rbs () -> ([untyped, untyped] | [untyped, untyped, untyped] | false | nil)
      def next_token
        raise NotImplementedError, "(input):1:1: next_token must be implemented"
      end

      # Override to recover from syntax errors. The default always raises.
      # @rbs (Integer token_id, untyped value, Array[untyped] value_stack) -> untyped
      def on_error(token_id, value, _value_stack)
        expected = expected_tokens
        token_name = token_to_str(token_id)
        state = @state_stack.last
        raise ParseError.new(
          token_id: token_id,
          token_name: token_name,
          token_value: value,
          expected_tokens: expected,
          location: @lookahead_location,
          state: state,
          suggestions: token_suggestions(token_name, expected),
          detail: parser_tables.fetch(:error_messages, EMPTY_ROW)[state]
        )
      end

      # Called after an ordinary input token is shifted. Override to observe
      # the internal token id, semantic value, and destination state.
      # @rbs (Integer token_id, untyped value, Integer state) -> void
      def on_shift(_token_id, _value, _state); end

      # Called after a production's semantic action and goto are committed.
      # Override to observe its id, RHS values, and semantic result.
      # @rbs (Integer production_id, Array[untyped] values, untyped result) -> void
      def on_reduce(_production_id, _values, _result); end

      # Called after the synthetic error token enters a recovery state.
      # The payload describes the original error before recovery popped stacks.
      # @rbs (Integer token_id, untyped value, Array[untyped] value_stack) -> void
      def on_error_recover(_token_id, _value, _value_stack); end

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
        return [] if @state_stack.empty?

        state = @state_stack.last
        parser_tables.fetch(:token_names).keys.filter_map do |token_id|
          action = table_lookup(parser_tables.fetch(:actions), state, token_id) || default_action(state) || [:error]
          token_to_str(token_id) unless error_action?(action) || token_id == ERROR_TOKEN
        end
      end

      private

      # @rbs (^() -> untyped source) -> untyped
      def drive_parser(source)
        ensure_driver_available!
        if @push_status == :active
          raise ParseError, "(input):1:1: cannot start another parser driver during an active push session"
        end

        @driver_status = :pull
        begin
          prepare_parse(source)
          loop do
            action = action_for_current_state
            outcome = perform(action)
            return outcome[1] if %i[accepted done].include?(outcome[0])
          end
        ensure
          @source = nil
          @driver_status = :idle
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
          if %i[accepted done].include?(outcome.first)
            finish_push_session
            return [:accepted, outcome.fetch(1)] if outcome.first == :accepted

            return [:rejected, outcome.fetch(1)]
          end
          return :need_more if @lookahead.equal?(NO_LOOKAHEAD)
        end
      end

      # @rbs () { () -> untyped } -> untyped
      def run_push_driver
        @driver_status = :push
        yield
      rescue StandardError
        finish_push_session
        raise
      ensure
        @driver_status = :idle
      end

      # @rbs () -> void
      def ensure_driver_available!
        return if @driver_status == :idle

        raise ParseError, "(input):1:1: parser driver is already running"
      end

      # @rbs () -> void
      def finish_push_session
        @push_status = :finished
        @source = nil
        @lookahead = NO_LOOKAHEAD
        @lookahead_location = nil
      end

      # @rbs (^() -> untyped source) -> void
      def prepare_parse(source)
        validate_parser_table_format!
        @source = source
        @state_stack = [0]
        @value_stack = []
        @lookahead = NO_LOOKAHEAD
        @lookahead_value = nil
        @lookahead_location = nil
        @recovery_shifts = 0
        @semantic_error = false
        @accept_requested = false
        @unknown_token_id = nil
        trace("start state 0")
      end

      # @rbs () -> void
      def validate_parser_table_format!
        tables = parser_tables
        unless tables.key?(:format_version)
          raise ParseError,
                "(tables):1:1: parser tables for #{self.class} are missing :format_version; " \
                "regenerate the parser with the installed Ibex version"
        end

        actual = tables.fetch(:format_version)
        return if actual == PARSER_TABLE_FORMAT_VERSION

        raise ParseError,
              "(tables):1:1: unsupported parser table format version #{actual.inspect} for #{self.class}; " \
              "runtime supports #{PARSER_TABLE_FORMAT_VERSION}; regenerate the parser with the installed Ibex version"
      end

      # @rbs () -> untyped
      def action_for_current_state
        read_lookahead if @lookahead.equal?(NO_LOOKAHEAD)
        state = @state_stack.last
        return [:error] unless parser_tables.fetch(:token_names).key?(@lookahead)

        explicit = table_lookup(parser_tables.fetch(:actions), state, @lookahead)
        return explicit if explicit

        default_action(state) || [:error]
      end

      # @rbs (untyped action) -> untyped
      def perform(action)
        case action.first
        when :shift then shift(action.fetch(1))
        when :reduce then reduce(action.fetch(1))
        when :accept then [:accepted, @value_stack.last]
        when :error then recover
        else raise ParseError, "(tables):1:1: unknown parser action #{action.inspect}"
        end
      end

      # @rbs (Integer next_state) -> untyped
      def shift(next_state)
        token_id = @lookahead
        value = @lookahead_value
        trace("shift #{token_to_str(token_id)} -> state #{next_state}")
        @state_stack << next_state
        @value_stack << value
        @lookahead = NO_LOOKAHEAD
        @lookahead_location = nil
        @recovery_shifts -= 1 if @recovery_shifts.positive?
        on_shift(token_id, value, next_state)
        [:continue]
      end

      # @rbs (Integer production_id) -> untyped
      def reduce(production_id)
        production = parser_tables.fetch(:productions).fetch(production_id)
        length = production.fetch(:length)
        values = @value_stack.last(length)
        hook_values = values.dup
        @state_stack.pop(length)
        @value_stack.pop(length)
        result = reduction_value(production, values)
        next_state = table_lookup(parser_tables.fetch(:gotos), @state_stack.last, production.fetch(:lhs))
        raise ParseError, "(tables):1:1: missing goto for production #{production_id}" if next_state.nil?

        @state_stack << next_state
        @value_stack << result
        trace("reduce #{production_id} (#{length}) -> state #{next_state}")
        on_reduce(production_id, hook_values, result)
        return [:accepted, result] if @accept_requested
        return recover(report: false) if @semantic_error

        [:continue]
      end

      # @rbs (Hash[Symbol, untyped] production, Array[untyped] values) -> untyped
      def reduction_value(production, values)
        action = production[:action]
        return values.first unless action
        return instance_exec(values, @value_stack.dup, &action) if action.respond_to?(:call)

        __send__(action, values, @value_stack.dup)
      end

      # @rbs (?report: bool) -> untyped
      def recover(report: true)
        @semantic_error = false
        if @recovery_shifts.positive?
          return [:done, nil] if @lookahead == EOF_TOKEN

          trace("discard #{token_to_str(@lookahead)} during recovery")
          @lookahead = NO_LOOKAHEAD
          @lookahead_location = nil
          return [:continue]
        end

        token_id = @lookahead
        value = @lookahead_value
        value_stack = @value_stack.dup
        on_error(token_id, value, value_stack.dup) if report
        return [:done, nil] unless shift_error_token

        @recovery_shifts = RECOVERY_SHIFTS
        on_error_recover(token_id, value, value_stack)
        [:continue]
      end

      # @rbs () -> bool
      def shift_error_token
        loop do
          action = table_lookup(parser_tables.fetch(:actions), @state_stack.last, ERROR_TOKEN)
          if action&.first == :shift
            trace("recover: shift error -> state #{action.fetch(1)}")
            @state_stack << action.fetch(1)
            @value_stack << nil
            return true
          end
          return false if @state_stack.length == 1

          trace("recover: pop state #{@state_stack.last}")
          @state_stack.pop
          @value_stack.pop
        end
      end

      # @rbs () -> void
      def read_lookahead
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
        trace("read #{token_to_str(@lookahead)}")
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

      # @rbs (untyped table, Integer row, Integer column) -> untyped
      def table_lookup(table, row, column)
        return table.lookup(row, column) if table.respond_to?(:lookup)

        table.fetch(row, EMPTY_ROW)[column]
      end

      # @rbs (String message) -> void
      def trace(message)
        @yydebug_output.puts("ibex: #{message}") if @yydebug
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
