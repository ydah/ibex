# frozen_string_literal: true
# rbs_inline: enabled

require_relative "lexer_input" unless defined?(Ibex::Runtime::LexerInput)

module Ibex
  module Runtime
    # Runtime contract mixed into parser classes that declare a lexer.
    # rubocop:disable Metrics/ModuleLength -- matching, actions, state, and positions share one session invariant.
    # @rbs module-self Parser
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
      # @rbs @lexer_pending_trivia: Array[CST::Trivia | CST::GreenTrivia]
      # @rbs @lexer_has_token: bool

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
        @lexer_pending_trivia = []
        @lexer_has_token = false
        self
      end

      # Lex and parse one String, IO, or Fiber source.
      # @rbs (String | IO | Fiber source, ?file: String) -> untyped
      def parse(source, file: "(input)")
        lex(source, file: file)
        parser = self #: Parser
        parser.do_parse
      rescue ParseError => e
        raise unless parser_tables[:cst]

        parser = self #: Parser
        parser.__send__(:cst_lexical_failure, e)
      end

      # Parse one generated-lexer source and return its semantic and syntax results.
      # @rbs (String | IO | Fiber source, ?file: String) -> CST::ParseResult
      def parse_with_syntax(source, file: "(input)")
        lex(source, file: file)
        parser = self #: Parser
        value = parser.do_parse
        parser.__send__(:syntax_parse_result, value)
      rescue ParseError => e
        raise unless parser_tables[:cst]

        parser = self #: Parser
        value = parser.__send__(:cst_lexical_failure, e)
        parser.__send__(:syntax_parse_result, value)
      end

      # Parse without executing parser production actions.
      # Lexer actions still run because they define tokenization and lexer state.
      # @rbs (String source, ?file: String) -> CST::SyntaxResult
      def parse_syntax(source, file: "(input)")
        parse_syntax_with_cache(CST::SourceText.new(source, file: file), CST::NodeCache.new)
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
          unless ensure_lexer_data?(input)
            location = lexer_zero_width_location.merge(ibex_lexer_start_state: lexer_state).freeze
            location = attach_cst_trivia(location) if red_green_cst?
            return [nil, nil, location]
          end

          rule, lexeme = select_lexer_match(input)
          raise_lexer_no_match(input) unless rule && lexeme

          location = consume_lexer_match(input, lexeme)
                     .merge(ibex_lexer_start_state: lexer_state).freeze
          emitted = apply_lexer_rule(rule, lexeme, location)
          return emitted if emitted
        end
      end

      private

      # @rbs (CST::SourceText source_text, CST::NodeCache cache) -> CST::SyntaxResult
      def parse_syntax_with_cache(source_text, cache)
        parser = self #: Parser
        parser.__send__(:with_syntax_only, cache) do
          lex(source_text.text, file: source_text.file || "(input)")
          value = begin
            parser.do_parse
          rescue ParseError => e
            raise unless parser_tables[:cst]

            parser.__send__(:cst_lexical_failure, e)
          end
          parsed = parser.__send__(:syntax_parse_result, value)
          CST::SyntaxResult.new(
            syntax_root: parsed.syntax_root,
            diagnostics: parsed.diagnostics,
            reused_ratio: 0.0
          )
        end
      end

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
        if emission.is_a?(Array)
          attached = attach_cst_trivia(location.merge(ibex_cst_text: lexeme).freeze)
          @lexer_has_token = true
          return [emission.fetch(0), emission.fetch(1), attached]
        end

        if @lexer_skip_requested
          retain_cst_trivia(lexeme, location)
          return nil
        end
        if rule.fetch(:kind) == :token
          attached = attach_cst_trivia(location.merge(ibex_cst_text: lexeme).freeze)
          @lexer_has_token = true
          return [rule.fetch(:token), value, attached]
        end

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

      # @rbs (String text, Hash[Symbol, untyped] location) -> void
      def retain_cst_trivia(text, location)
        return if cst_trivia_policy == :drop

        value = if red_green_cst?
                  CST::GreenTrivia.new(kind: cst_trivia_kind(text), text: text)
                else
                  CST::Trivia.new(text: text, location: location)
                end
        @lexer_pending_trivia << value
      end

      # @rbs (Hash[Symbol, untyped] location) -> Hash[Symbol, untyped]
      def attach_cst_trivia(location)
        trivia = @lexer_pending_trivia
        return location if trivia.empty? || cst_trivia_policy == :drop

        leading = trivia.dup
        trailing = [] #: Array[CST::GreenTrivia]
        if red_green_cst? && cst_trivia_policy == :balanced && @lexer_has_token
          green = green_trivia_values(leading)
          trailing, leading = split_balanced_trivia(green)
        end
        attached = location.merge(
          leading_trivia: leading.freeze,
          cst_previous_trailing: trailing.freeze
        ).freeze
        trivia.clear
        attached
      end

      # @rbs () -> Array[CST::Trivia]
      def take_cst_trailing_trivia
        trivia = @lexer_pending_trivia
        result = if cst_trivia_policy == :leading && !red_green_cst?
                   trivia.grep(CST::Trivia).freeze
                 else
                   Array.new(0).freeze
                 end #: Array[CST::Trivia]
        trivia.clear
        result
      end

      # @rbs () -> Symbol
      def cst_trivia_policy
        config = parser_tables[:cst]
        return config.fetch(:trivia_policy) if config.is_a?(Hash)

        policy = parser_tables.fetch(:cst_trivia, :drop)
        policy == :attach ? :leading : policy
      end

      # @rbs () -> bool
      def red_green_cst?
        parser_tables.fetch(:format_version) >= 6 && parser_tables[:cst].is_a?(Hash)
      end

      # @rbs (String text) -> Integer
      def cst_trivia_kind(text)
        config = parser_tables.fetch(:cst)
        kinds = config.fetch(:kinds).fetch(:trivia)
        name = if text.include?("\n")
                 "newline"
               elsif text.match?(/\A[[:space:]]+\z/)
                 "whitespace"
               elsif text.start_with?("//", "#")
                 "line_comment"
               elsif text.start_with?("/*")
                 "block_comment"
               else
                 "custom_skip"
               end
        kinds.fetch(name)
      end

      # @rbs (Array[CST::GreenTrivia] trivia) -> [Array[CST::GreenTrivia], Array[CST::GreenTrivia]]
      def split_balanced_trivia(trivia)
        before = [] #: Array[CST::GreenTrivia]
        after = [] #: Array[CST::GreenTrivia]
        found = false
        trivia.each do |item|
          if found
            after << item
            next
          end
          newline = item.text.index("\n".b)
          unless newline
            before << item
            next
          end

          boundary = newline + 1
          before_text = item.text.byteslice(0, boundary) || "".b
          after_text = item.text.byteslice(boundary, item.text.bytesize - boundary) || "".b
          before << CST::GreenTrivia.new(kind: cst_trivia_kind(before_text), text: before_text)
          after << CST::GreenTrivia.new(kind: cst_trivia_kind(after_text), text: after_text) unless after_text.empty?
          found = true
        end
        [before, after]
      end

      # @rbs () -> CST::SourceText
      def cst_source_text
        input = @lexer_input || raise(ParseError, "(lexer):1:1: lexer input is unavailable")
        CST::SourceText.new(input.source_bytes.byteslice(0, @lexer_byte_offset || 0) || "".b, file: @lexer_file)
      end

      # @rbs () -> Array[CST::GreenTrivia]
      def take_cst_pending_green_trivia
        values = green_trivia_values(@lexer_pending_trivia)
        @lexer_pending_trivia.clear
        values
      end

      # @rbs (Array[CST::Trivia | CST::GreenTrivia] values) -> Array[CST::GreenTrivia]
      def green_trivia_values(values)
        result = [] #: Array[CST::GreenTrivia]
        values.each { |item| result << item if item.is_a?(CST::GreenTrivia) }
        result
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
