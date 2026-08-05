# frozen_string_literal: true

require_relative "declaration_lexer_state"

module Ibex
  module Frontend
    class TokenAdapter
      # Classifies tokens through the class header and declaration section.
      # rubocop:disable Metrics/ClassLength, Metrics/CyclomaticComplexity
      # One state machine owns declaration-boundary classification.
      class DeclarationState
        include DeclarationDocumentState
        include DeclarationLexerState

        DECLARATIONS = {
          "include" => %i[INCLUDE include_path],
          "import" => %i[IMPORT include_path],
          "token" => %i[TOKEN token_symbols], "options" => %i[OPTIONS options_identifiers],
          "expect" => %i[EXPECT expect_integer], "start" => %i[START start_first_symbol],
          "expect_rr" => %i[EXPECT_RR expect_rr_integer],
          "recover" => %i[RECOVER recover_kind],
          "on_error_reduce" => %i[ON_ERROR_REDUCE on_error_reduce_first_symbol],
          "test" => %i[TEST test_expectation],
          "lexer" => %i[LEXER lexer_entries],
          "convert" => %i[CONVERT convert_name], "pragma" => %i[PRAGMA pragma_value],
          "display" => %i[DISPLAY display_symbol], "type" => %i[TYPE type_symbol],
          "param" => %i[PARAM param_name],
          "printer" => %i[PRINTER printer_symbol],
          "rule" => %i[RULE rules]
        }.freeze #: Hash[String, [external_token, Symbol]]
        ASSOCIATIONS = {
          "left" => :LEFT, "right" => :RIGHT, "nonassoc" => :NONASSOC, "precedence" => :PRECEDENCE
        }.freeze #: Hash[String, external_token]
        SCALAR_TYPES = {
          literal: :LITERAL, regexp: :REGEXP, integer: :INTEGER, action: :ACTION, user_code: :USER_CODE
        }.freeze #: Hash[Symbol, external_token]
        EXPECTATIONS = {
          class_keyword: "class", class_name: "identifier", superclass_name: "identifier",
          expect_integer: "integer", expect_rr_integer: "integer",
          start_first_symbol: "a grammar symbol", start_symbols: "a grammar symbol",
          include_path: "a double-quoted relative path",
          display_symbol: "a grammar symbol", type_symbol: "a grammar symbol",
          display_value: "a quoted string", type_value: "a quoted string",
          param_name: "an identifier", param_type: "a quoted type or declaration",
          printer_symbol: "a grammar symbol", printer_action: "an action",
          recover_kind: "sync", recovery_colon: ":", recovery_first_symbol: "a grammar symbol",
          recovery_symbols: "a grammar symbol", on_error_reduce_first_symbol: "a grammar symbol",
          on_error_reduce_symbols: "a grammar symbol", test_expectation: "accept or reject",
          test_source: "a double-quoted string",
          lexer_entries: "a lexer rule, state, or end", lexer_state_name: "a state name",
          lexer_state_do: "do", lexer_pattern: "a regular expression or quoted literal",
          lexer_action_or_entry: "an action, lexer rule, state, or end"
        }.freeze #: Hash[Symbol, String]

        attr_reader :conversion_name #: Token?
        attr_reader :declaration #: Symbol?
        attr_reader :precedence_closer #: String?
        attr_reader :state #: Symbol

        # @rbs @extended_mode: bool
        # @rbs @fragment: bool?
        # @rbs @pragmas: Hash[String, Location]
        # @rbs @pragma_location: Location?

        # @rbs (?extended: bool) -> void
        def initialize(extended: false)
          @extended_mode = extended
          @pragmas = {} #: Hash[String, Location]
          @state = :class_keyword
        end

        # @rbs (Token token, Array[Token] remaining) -> external_token
        def classify(token, remaining)
          return classify_identifier(token, remaining) if token.type == :identifier
          return classify_scalar(token, remaining) if SCALAR_TYPES.key?(token.type)

          classify_punctuation(token)
        end

        # @rbs () -> bool
        def rules?
          @state == :rules
        end

        # @rbs () -> bool
        def extended_pragma?
          @pragmas.key?("extended")
        end

        # @rbs () -> bool
        def cst_pragma?
          @pragmas.key?("cst")
        end

        # @rbs () -> Location?
        def extended_pragma_location
          @pragmas["extended"]
        end

        # @rbs () -> Location?
        def cst_pragma_location
          @pragmas["cst"]
        end

        # @rbs (Token? token) -> String?
        def expectation(token)
          return "identifier" if @state == :pragma_value && token&.type != :identifier

          expected = EXPECTATIONS[@state]
          return expected if expected

          if @declaration == :precedence
            precedence_expectation(token)
          elsif @declaration == :convert
            "end"
          elsif @state == :declaration
            token&.type == :eof ? "rule" : "a declaration or rule"
          end
        end

        private

        # @rbs (Token token, Array[Token] remaining) -> external_token
        def classify_identifier(token, remaining)
          return classify_lexer_identifier(token) if lexer_declaration_state?

          case @state
          when :class_keyword then class_keyword(token)
          when :class_name, :superclass_name then constant_name(remaining)
          when :declaration, :param_type then begin_declaration(token)
          when :token_symbols
            @token_alias_candidate = token
            declaration_symbol(token)
          when :options_identifiers, :start_symbols, :recovery_symbols, :on_error_reduce_symbols
            declaration_symbol(token)
          when :precedence_association, :precedence_symbols then precedence_identifier(token)
          when :start_first_symbol then continue_start_symbols(:IDENTIFIER)
          when :display_symbol, :type_symbol then begin_metadata_value(:IDENTIFIER)
          when :param_name then begin_param_type
          when :printer_symbol then begin_printer_action(:IDENTIFIER)
          when :recover_kind then begin_recovery_colon(token)
          when :recovery_first_symbol then continue_recovery_symbols(:IDENTIFIER)
          when :on_error_reduce_first_symbol then continue_on_error_reduce_symbols(:IDENTIFIER)
          when :test_expectation then begin_test_source(token)
          when :pragma_value then finish_pragma(token)
          when :convert_name then begin_conversion(token, :IDENTIFIER, remaining)
          else :IDENTIFIER
          end
        end

        # @rbs (Array[Token] remaining) -> external_token
        def constant_name(remaining)
          following = remaining.first
          raise Ibex::Error, "unexpected end of token stream" unless following

          @state = if following.type == :scope
                     @state
                   elsif following.type == :<
                     :superclass_marker
                   else
                     :declaration
                   end
          :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def begin_declaration(token)
          value = string_value(token)
          return begin_precedence(token) if %w[prechigh preclow].include?(value)

          reject_fragment_pragma(token, value)

          terminal, next_state = DECLARATIONS[value]
          return :IDENTIFIER unless terminal

          @pragma_location = token.location if terminal == :PRAGMA
          @token_alias_candidate = nil
          @state = next_state
          @declaration = value.to_sym unless terminal == :RULE
          @declaration = nil if terminal == :RULE
          terminal
        end

        # @rbs (Token token) -> external_token
        def finish_pragma(token)
          value = string_value(token)
          raise Ibex::Error, "#{token.location}: unknown pragma #{value}" unless %w[extended cst].include?(value)

          location = @pragma_location || token.location
          raise Ibex::Error, "#{location}: duplicate pragma #{value}" if @pragmas[value]

          @pragmas[value] = location
          @pragma_location = nil
          @state = :declaration
          @declaration = nil
          :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def begin_precedence(token)
          high_to_low = string_value(token) == "prechigh"
          @precedence_closer = high_to_low ? "preclow" : "prechigh"
          @declaration = :precedence
          @state = :precedence_association
          high_to_low ? :PRECHIGH : :PRECLOW
        end

        # @rbs (Token token) -> external_token
        def declaration_symbol(token)
          return begin_declaration(token) if declaration_boundary?(string_value(token))

          :IDENTIFIER
        end

        # @rbs (String value) -> bool
        def declaration_boundary?(value)
          return false if %w[display type param printer].include?(value) && !extended_features?

          DECLARATIONS.key?(value) || %w[prechigh preclow].include?(value)
        end

        # @rbs () -> bool
        def extended_features?
          @extended_mode || extended_pragma? || cst_pragma?
        end

        # @rbs (Token token) -> external_token
        def precedence_identifier(token)
          value = string_value(token)
          return finish_precedence(token) if value == @precedence_closer

          association = ASSOCIATIONS[value]
          @state = :precedence_symbols if association
          association || :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def finish_precedence(token)
          @state = :declaration
          @declaration = nil
          @precedence_closer = nil
          string_value(token) == "prechigh" ? :PRECHIGH : :PRECLOW
        end

        # @rbs (Token token, external_token type, Array[Token] remaining) -> external_token
        def begin_conversion(token, type, remaining)
          if token.type == :identifier && token.value == "end"
            @state = :declaration
            @declaration = nil
            return :END
          end

          validate_conversion_line(token, remaining)
          @conversion_name = token
          @state = :convert_expression
          type
        end

        # @rbs (Token token, Array[Token] remaining) -> external_token
        def classify_scalar(token, remaining)
          type = SCALAR_TYPES.fetch(token.type)
          classified = classify_lexer_scalar(type) ||
                       classify_token_alias(token, type) || classify_include(type) || classify_single_symbol(type) ||
                       classify_metadata(type) || classify_printer(type) || classify_grammar_test(type) ||
                       classify_conversion(token, type, remaining)

          classified || type
        end

        # @rbs (external_token type) -> external_token?
        def classify_single_symbol(type)
          return finish_single_symbol(type) if %i[expect_integer expect_rr_integer].include?(@state) && type == :INTEGER

          first = continue_first_symbol(type)
          return first if first

          type if @state == :start_symbols && type == :LITERAL
        end

        # @rbs (external_token type) -> external_token?
        def continue_first_symbol(type)
          return unless type == :LITERAL
          return continue_start_symbols(type) if @state == :start_first_symbol
          return continue_recovery_symbols(type) if @state == :recovery_first_symbol

          continue_on_error_reduce_symbols(type) if @state == :on_error_reduce_first_symbol
        end

        # @rbs (Token token, external_token type) -> external_token?
        def classify_token_alias(token, type)
          candidate = @token_alias_candidate
          return unless extended_features? && @state == :token_symbols &&
                        type == :LITERAL && candidate
          return unless candidate.location.line == token.location.line

          @token_alias_candidate = nil
          :TOKEN_ALIAS
        end

        # @rbs (external_token type) -> external_token?
        def classify_metadata(type)
          return unless type == :LITERAL
          return begin_metadata_value(type) if %i[display_symbol type_symbol].include?(@state)
          return finish_param_type(type) if @state == :param_type

          finish_metadata_value(type) if %i[display_value type_value].include?(@state)
        end

        # @rbs (external_token type) -> external_token?
        def classify_printer(type)
          return begin_printer_action(type) if @state == :printer_symbol && type == :LITERAL
          return unless @state == :printer_action && type == :ACTION

          @state = :declaration
          @declaration = nil
          type
        end

        # @rbs (external_token type) -> external_token?
        def classify_grammar_test(type)
          return unless @state == :test_source && type == :LITERAL

          @state = :declaration
          @declaration = nil
          type
        end

        # @rbs (Token token, external_token type, Array[Token] remaining) -> external_token?
        def classify_conversion(token, type, remaining)
          return unless type == :LITERAL
          return begin_conversion(token, type, remaining) if @state == :convert_name

          finish_conversion(type) if @state == :convert_expression
        end

        # @rbs (external_token type) -> external_token
        def finish_single_symbol(type)
          @state = :declaration
          @declaration = nil
          type
        end

        # @rbs (external_token type) -> external_token
        def continue_start_symbols(type)
          @state = :start_symbols
          type
        end

        # @rbs (external_token type) -> external_token
        def continue_recovery_symbols(type)
          @state = :recovery_symbols
          type
        end

        # @rbs (external_token type) -> external_token
        def continue_on_error_reduce_symbols(type)
          @state = :on_error_reduce_symbols
          type
        end

        # @rbs (external_token type) -> external_token
        def begin_metadata_value(type)
          @state = @state == :display_symbol ? :display_value : :type_value
          type
        end

        # @rbs () -> external_token
        def begin_param_type
          @state = :param_type
          :IDENTIFIER
        end

        # @rbs (external_token type) -> external_token
        def begin_printer_action(type)
          @state = :printer_action
          type
        end

        # @rbs (Token token) -> external_token
        def begin_recovery_colon(_token)
          @state = :recovery_colon
          :IDENTIFIER
        end

        # @rbs (Token token) -> external_token
        def begin_test_source(_token)
          @state = :test_source
          :IDENTIFIER
        end

        # @rbs (external_token type) -> external_token
        def finish_param_type(type)
          @state = :declaration
          @declaration = nil
          type
        end

        # @rbs (external_token type) -> external_token
        def finish_metadata_value(type)
          @state = :declaration
          @declaration = nil
          type
        end

        # @rbs (external_token type) -> external_token
        def finish_conversion(type)
          @state = :convert_name
          @conversion_name = nil
          type
        end

        # @rbs (Token token) -> external_token
        def classify_punctuation(token)
          @state = :superclass_name if @state == :superclass_marker && token.type == :<
          @state = :recovery_first_symbol if @state == :recovery_colon && token.type == :":"
          string_value(token)
        end

        # @rbs (Token name, Array[Token] remaining) -> void
        def validate_conversion_line(name, remaining)
          line = name.location.line
          rest = remaining.take_while do |token|
            token.type != :eof && token.location.line == line && !(token.type == :identifier && token.value == "end")
          end
          return if rest.length == 1 && rest.first.type == :literal

          raise Ibex::Error, "#{name.location}: expected a quoted Ruby conversion expression"
        end

        # @rbs (Token? token) -> String?
        def precedence_expectation(token)
          return @precedence_closer if token&.type == :eof

          "left or right or nonassoc or precedence" if @state == :precedence_association
        end

        # @rbs (Token token) -> String
        def string_value(token)
          value = token.value
          return value if value.is_a?(String)

          raise Ibex::Error, "#{token.location}: expected text token"
        end
      end
      # rubocop:enable Metrics/ClassLength, Metrics/CyclomaticComplexity
    end
  end
end
