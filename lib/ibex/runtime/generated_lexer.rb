# frozen_string_literal: true
# rbs_inline: enabled

require_relative "lexer_input" unless defined?(Ibex::Runtime::LexerInput)

module Ibex
  module Runtime
    # Runtime contract mixed into parser classes that declare a lexer.
    # rubocop:disable Metrics/ModuleLength -- matching, actions, state, and positions share one session invariant.
    module GeneratedLexer
      NO_EMISSION = Object.new.freeze #: Object

      # @rbs @lexer_input: LexerInput?
      # @rbs @lexer_file: String
      # @rbs @lexer_states: Array[String]
      # @rbs @lexer_line: Integer
      # @rbs @lexer_column: Integer
      # @rbs @lexer_byte_column: Integer
      # @rbs @lexer_byte_offset: Integer
      # @rbs @lexer_lexeme: String?
      # @rbs @lexer_emission: Object | Array[untyped]
      # @rbs @lexer_skip_requested: bool

      # Reset the generated lexer to the beginning of an input.
      # @rbs (String | IO | Fiber source, ?file: String) -> self
      def lex(source, file: "(input)")
        @lexer_input = LexerInput.new(source)
        @lexer_file = file
        @lexer_states = ["INITIAL"]
        @lexer_line = 1
        @lexer_column = 1
        @lexer_byte_column = 1
        @lexer_byte_offset = 0
        @lexer_lexeme = nil
        @lexer_emission = NO_EMISSION
        @lexer_skip_requested = false
        self
      end

      # Lex and parse one String, IO, or Fiber source.
      # @rbs (String | IO | Fiber source, ?file: String) -> untyped
      def parse(source, file: "(input)")
        lex(source, file: file)
        parser = self #: Parser
        parser.do_parse
      end

      # Return the current named lexer state.
      # @rbs () -> Symbol
      def lexer_state
        (@lexer_states || ["INITIAL"]).last.to_sym
      end

      # Replace the current named lexer state.
      # @rbs (Symbol | String state) -> Symbol
      def lexer_state=(state)
        name = validate_lexer_state(state)
        states = @lexer_states ||= ["INITIAL"]
        states[-1] = name
        name.to_sym
      end

      # Pull one token using longest match and declaration-order tie breaking.
      # @rbs () -> [untyped, untyped, Hash[Symbol, untyped]]
      def next_token
        input = @lexer_input
        raise ParseError, "(lexer):1:1: call parse or lex before next_token" unless input

        loop do
          return [nil, nil, lexer_zero_width_location] unless ensure_lexer_data?(input)

          rule, lexeme = select_lexer_match(input)
          raise_lexer_no_match(input) unless rule && lexeme

          location = consume_lexer_match(input, lexeme)
          emitted = apply_lexer_rule(rule, lexeme, location)
          return emitted if emitted
        end
      end

      private

      # @rbs (LexerInput input) -> bool
      def ensure_lexer_data?(input)
        input.read_more? while input.buffer.empty? && !input.eof?
        !input.buffer.empty?
      end

      # @rbs (LexerInput input) -> [Hash[Symbol, untyped]?, String?]
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def select_lexer_match(input)
        loop do
          matches = lexer_rules.filter_map do |rule|
            match = rule.fetch(:regexp).match(input.buffer)
            [rule, match[0]] if match&.begin(0)&.zero?
          end #: Array[[Hash[Symbol, untyped], String]]
          boundary_match = matches.any? { |_rule, lexeme| lexeme.length == input.buffer.length }
          if !input.eof? && (matches.empty? || boundary_match)
            input.read_more?
            next
          end

          selected = matches.max_by { |rule, lexeme| [lexeme.bytesize, -rule.fetch(:id)] }
          return [nil, nil] unless selected

          return selected
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # @rbs () -> Array[Hash[Symbol, untyped]]
      def lexer_rules
        tables = self.class.const_get(:LEXER_RULES_BY_STATE)
        rules = tables[lexer_state]
        return rules if rules

        raise ParseError, "(lexer):1:1: missing rules for lexer state #{lexer_state}"
      end

      # @rbs (LexerInput input) -> bot
      def raise_lexer_no_match(input)
        location = lexer_zero_width_location
        excerpt = input.buffer.slice(0, 16)
        raise ParseError.new(
          token_name: "lexer input", token_value: excerpt, location: location,
          detail: "no lexer rule matches #{excerpt.inspect} in state #{lexer_state}"
        )
      end

      # @rbs (LexerInput input, String lexeme) -> Hash[Symbol, untyped]
      def consume_lexer_match(input, lexeme)
        start = lexer_position
        input.consume(lexeme)
        advance_lexer_position(lexeme)
        finish = lexer_position
        {
          file: @lexer_file, line: start.fetch(:line), column: start.fetch(:column),
          grapheme_column: start.fetch(:column), byte_column: start.fetch(:byte_column),
          end_line: finish.fetch(:line), end_column: finish.fetch(:column),
          end_grapheme_column: finish.fetch(:column), end_byte_column: finish.fetch(:byte_column),
          start_byte: start.fetch(:byte), end_byte: finish.fetch(:byte),
          source_line: input.source_line(start.fetch(:line))
        }
      end

      # @rbs (Hash[Symbol, untyped] rule, String lexeme, Hash[Symbol, untyped] location) ->
      #   [untyped, untyped, Hash[Symbol, untyped]]?
      def apply_lexer_rule(rule, lexeme, location)
        @lexer_lexeme = lexeme
        @lexer_emission = NO_EMISSION
        @lexer_skip_requested = rule.fetch(:kind) == :skip
        action = rule[:action]
        value = action ? __send__(action, lexeme) : lexeme
        emission = @lexer_emission
        return [emission.fetch(0), emission.fetch(1), location] if emission.is_a?(Array)
        return nil if @lexer_skip_requested
        return [rule.fetch(:token), value, location] if rule.fetch(:kind) == :token

        raise ParseError, "#{location.fetch(:file)}:#{location.fetch(:line)}:" \
                          "#{location.fetch(:column)}: on lexer rule did not emit or skip"
      ensure
        @lexer_lexeme = nil
      end

      # Emit a token from a lexer action.
      # @rbs (untyped token, ?untyped value) -> untyped
      def emit(token, value = NO_EMISSION)
        actual = value.equal?(NO_EMISSION) ? @lexer_lexeme : value
        @lexer_emission = [token, actual]
        actual
      end

      # Suppress the current match from a lexer action.
      # @rbs () -> nil
      def skip
        @lexer_skip_requested = true
        nil
      end

      # Return the text consumed by the active lexer action.
      # @rbs () -> String?
      def lexeme
        @lexer_lexeme
      end

      # Push a named lexer state.
      # @rbs (Symbol | String state) -> Symbol
      def push_state(state)
        name = validate_lexer_state(state)
        (@lexer_states ||= ["INITIAL"]) << name
        name.to_sym
      end

      # Pop the current named lexer state.
      # @rbs () -> Symbol
      def pop_state
        states = @lexer_states ||= ["INITIAL"]
        raise ParseError, "(lexer):1:1: cannot pop the INITIAL lexer state" if states.one?

        (states.pop || "INITIAL").to_sym
      end

      # @rbs (Symbol | String state) -> String
      def validate_lexer_state(state)
        name = state.to_s
        known = self.class.const_get(:LEXER_STATES)
        raise ArgumentError, "unknown lexer state #{state.inspect}" unless known.include?(name)

        name
      end

      # @rbs () -> Hash[Symbol, Integer]
      def lexer_position
        {
          line: @lexer_line || 1, column: @lexer_column || 1,
          byte_column: @lexer_byte_column || 1, byte: @lexer_byte_offset || 0
        }
      end

      # @rbs () -> Hash[Symbol, untyped]
      def lexer_zero_width_location
        position = lexer_position
        {
          file: @lexer_file || "(input)", line: position.fetch(:line), column: position.fetch(:column),
          grapheme_column: position.fetch(:column), byte_column: position.fetch(:byte_column),
          end_line: position.fetch(:line), end_column: position.fetch(:column),
          end_grapheme_column: position.fetch(:column), end_byte_column: position.fetch(:byte_column),
          start_byte: position.fetch(:byte), end_byte: position.fetch(:byte)
        }
      end

      # @rbs (String lexeme) -> void
      def advance_lexer_position(lexeme)
        lexeme.scan(/\X/).each do |value|
          grapheme = value.is_a?(String) ? value : value.join
          @lexer_byte_offset += grapheme.bytesize
          if grapheme.include?("\n")
            @lexer_line += 1
            @lexer_column = 1
            @lexer_byte_column = 1
          else
            @lexer_column += 1
            @lexer_byte_column += grapheme.bytesize
          end
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
