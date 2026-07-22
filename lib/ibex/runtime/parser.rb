# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Runtime
    # Parser-table shape understood by this runtime.
    PARSER_TABLE_FORMAT_VERSION = 1 #: Integer

    # Raised by the default parser error handler.
    class ParseError < StandardError; end

    # rubocop:disable Metrics/ClassLength

    # Drives a table-defined LR parser without native extensions.
    #
    # Subclasses provide `.parser_tables`, returning `:tokens`, `:token_names`,
    # `:actions`, `:gotos`, and `:productions`. Actions are represented by
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
      # @rbs @recovery_shifts: Integer
      # @rbs @semantic_error: bool
      # @rbs @accept_requested: bool
      # @rbs @unknown_token_id: Integer?
      # @rbs @unknown_token_name: String?

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
        @recovery_shifts = 0
        @semantic_error = false
        @accept_requested = false
        @unknown_token_id = nil
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

      # Override in pull parsers. Return `[token, value]`, `false`, or `nil`.
      # @rbs () -> ([untyped, untyped] | false | nil)
      def next_token
        raise NotImplementedError, "(input):1:1: next_token must be implemented"
      end

      # Override to recover from syntax errors. The default always raises.
      # @rbs (Integer token_id, untyped value, Array[untyped] value_stack) -> untyped
      def on_error(token_id, value, _value_stack)
        expected = expected_tokens
        suffix = expected.empty? ? "" : "; expected #{expected.join(', ')}"
        raise ParseError, "(input):1:1: unexpected #{token_to_str(token_id)}#{suffix} (#{value.inspect})"
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
        prepare_parse(source)
        loop do
          action = action_for_current_state
          outcome = perform(action)
          return outcome[1] if outcome[0] == :done
        end
      ensure
        @source = nil
      end

      # @rbs (^() -> untyped source) -> void
      def prepare_parse(source)
        validate_parser_table_format!
        @source = source
        @state_stack = [0]
        @value_stack = []
        @lookahead = NO_LOOKAHEAD
        @lookahead_value = nil
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
        when :accept then [:done, @value_stack.last]
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
        return [:done, result] if @accept_requested
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
        pair = read_external_token
        if pair.nil? || pair == false
          @lookahead = EOF_TOKEN
          @lookahead_value = nil
        else
          external_token, @lookahead_value = pair
          @lookahead = internal_token_id(external_token)
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
