# frozen_string_literal: true

module Ibex
  module Frontend
    # Re-runs the generated parser after suppressing only conservative source regions.
    class DiagnosticRecovery
      DECLARATION_STARTS = %w[
        pragma token prechigh preclow options expect expect_rr start recover on_error_reduce test
        convert display type param printer
      ].freeze #: Array[String]

      # @rbs @tokens: Array[Token]
      # @rbs @mode: Symbol
      # @rbs @max_diagnostics: Integer
      # @rbs @suppressed: Hash[Integer, bool]

      # @rbs (Array[Token] tokens, mode: Symbol, max_diagnostics: Integer) -> void
      def initialize(tokens, mode:, max_diagnostics:)
        @tokens = tokens
        @mode = mode
        @max_diagnostics = max_diagnostics
        @diagnostics = [] #: Array[Diagnostic]
        @suppressed = {} #: Hash[Integer, bool]
      end

      # @rbs () -> [AST::Root | AST::Fragment | nil, Array[Diagnostic]]
      def parse
        ast = parse_until_stable
        [ast, sorted_diagnostics]
      end

      private

      # @rbs () -> (AST::Root | AST::Fragment | nil)
      def parse_until_stable
        attempts = 0
        loop do
          parser = GeneratedParser.new(working_tokens, mode: @mode)
          begin
            return parser.parse
          rescue Ibex::Error => e
            return if @diagnostics.length >= @max_diagnostics

            diagnostic = diagnostic_from(e, parser.diagnostic_token, phase: :syntax)
            append_diagnostic(diagnostic)
            range = suppression_range(parser.diagnostic_token, e)
            return unless range && suppress(range)

            attempts += 1
            return if attempts >= @tokens.length
          end
        end
      end

      # @rbs () -> Array[Token]
      def working_tokens
        @tokens.each_with_index.filter_map { |token, index| token unless @suppressed[index] }
      end

      # @rbs (Diagnostic diagnostic) -> void
      def append_diagnostic(diagnostic)
        key = diagnostic_key(diagnostic)
        return if @diagnostics.any? { |existing| diagnostic_key(existing) == key }

        @diagnostics << diagnostic
      end

      # @rbs (Diagnostic diagnostic) -> [String, String, Integer, Integer, String]
      def diagnostic_key(diagnostic)
        location = diagnostic.location
        [diagnostic.phase.to_s, location.file, location.line, location.column, diagnostic.message]
      end

      # @rbs () -> Array[Diagnostic]
      def sorted_diagnostics
        @diagnostics.uniq { |diagnostic| diagnostic_key(diagnostic) }
                    .sort_by { |diagnostic| diagnostic_sort_key(diagnostic) }
                    .first(@max_diagnostics)
                    .freeze
      end

      # @rbs (Diagnostic diagnostic) -> [String, Integer, Integer, String, String]
      def diagnostic_sort_key(diagnostic)
        location = diagnostic.location
        [location.file, location.line, location.column, diagnostic.phase.to_s, diagnostic.code]
      end

      # @rbs (Token? token, Exception error) -> Range[Integer]?
      def suppression_range(token, error)
        index = token_index(token) || token_index_for_message(error.message)
        return unless index

        rule_marker = rule_marker_index
        return declaration_range(index, rule_marker) if rule_marker && index < rule_marker
        return rule_range(index, rule_marker) if rule_marker

        nil
      end

      # @rbs (Token? token) -> Integer?
      def token_index(token)
        return unless token

        @tokens.index { |candidate| candidate.equal?(token) }
      end

      # @rbs (String message) -> Integer?
      def token_index_for_message(message)
        @tokens.index { |token| message.start_with?("#{token.location}:") }
      end

      # @rbs () -> Integer?
      def rule_marker_index
        @tokens.index { |token| token.type == :identifier && token.value == "rule" }
      end

      # @rbs (Integer failure, Integer rule_marker) -> Range[Integer]?
      def declaration_range(failure, rule_marker)
        starts = (0...rule_marker).select { |index| declaration_start?(index) }
        start = starts.reverse.find { |index| index <= failure }
        return unless start

        finish = declaration_finish(start, rule_marker, starts)
        start...finish
      end

      # @rbs (Integer index) -> bool
      def declaration_start?(index)
        token = @tokens[index]
        token&.type == :identifier && DECLARATION_STARTS.include?(token.value)
      end

      # @rbs (Integer start, Integer rule_marker, Array[Integer] starts) -> Integer
      def declaration_finish(start, rule_marker, starts)
        value = @tokens.fetch(start).value
        return matching_declaration_end(start, rule_marker, value == "prechigh" ? "preclow" : "prechigh") if
          %w[prechigh preclow].include?(value)
        return matching_declaration_end(start, rule_marker, "end") if value == "convert"

        starts.find { |index| index > start } || rule_marker
      end

      # @rbs (Integer start, Integer fallback, String closer) -> Integer
      def matching_declaration_end(start, fallback, closer)
        index = ((start + 1)...fallback).find { |candidate| @tokens[candidate]&.value == closer }
        index ? index + 1 : fallback
      end

      # @rbs (Integer failure, Integer rule_marker) -> Range[Integer]?
      def rule_range(failure, rule_marker)
        grammar_end = grammar_end_index(rule_marker)
        definitions = rule_definition_starts(rule_marker, grammar_end)
        start = definitions.reverse.find { |index| index <= failure }
        return unless start

        finish = definitions.find { |index| index > start } || grammar_end
        alternative_range(failure, start, finish) || (start...finish)
      end

      # @rbs (Integer rule_marker) -> Integer
      def grammar_end_index(rule_marker)
        depth = 0
        ((rule_marker + 1)...@tokens.length).each do |index|
          token = @tokens.fetch(index)
          depth += 1 if token.type == :"("
          depth -= 1 if token.type == :")" && depth.positive?
          return index if depth.zero? && token.type == :identifier && token.value == "end"
        end
        @tokens.length - 1
      end

      # @rbs (Integer rule_marker, Integer grammar_end) -> Array[Integer]
      def rule_definition_starts(rule_marker, grammar_end)
        starts = [] #: Array[Integer]
        depth = 0
        lhs_column = nil #: Integer?
        ((rule_marker + 1)...grammar_end).each do |index|
          token = @tokens.fetch(index)
          depth += 1 if token.type == :"("
          depth -= 1 if token.type == :")" && depth.positive?
          next unless depth.zero? && lhs_candidate?(index, lhs_column)

          lhs_column ||= token.location.column
          starts << index
        end
        starts
      end

      # @rbs (Integer index, Integer? lhs_column) -> bool
      def lhs_candidate?(index, lhs_column)
        token = @tokens[index]
        following = @tokens[index + 1]
        return false unless token&.type == :identifier && following&.type == :":"

        lhs_column.nil? || token.location.column <= lhs_column
      end

      # @rbs (Integer failure, Integer start, Integer finish) -> Range[Integer]?
      def alternative_range(failure, start, finish)
        colon = ((start + 1)...finish).find { |index| @tokens[index]&.type == :":" }
        return unless colon

        pipes = top_level_pipes(colon + 1, finish)
        return if pipes.empty?

        previous = pipes.reverse.find { |index| index < failure }
        following = pipes.find { |index| index >= failure }
        alternative_slice(previous, following, colon, finish)
      end

      # @rbs (Integer? previous, Integer? following, Integer colon, Integer finish) -> Range[Integer]?
      def alternative_slice(previous, following, colon, finish)
        if previous
          following ? (previous...following) : (previous...finish)
        elsif following
          (colon + 1)..following
        end
      end

      # @rbs (Integer start, Integer finish) -> Array[Integer]
      def top_level_pipes(start, finish)
        depth = 0
        (start...finish).filter_map do |index|
          token = @tokens.fetch(index)
          depth += 1 if token.type == :"("
          depth -= 1 if token.type == :")" && depth.positive?
          index if depth.zero? && token.type == :|
        end
      end

      # @rbs (Range[Integer] range) -> bool
      def suppress(range)
        changed = false
        range.each do |index|
          next if index.negative? || index >= @tokens.length || @tokens[index]&.type == :eof
          next if @suppressed[index]

          @suppressed[index] = true
          changed = true
        end
        changed
      end

      # @rbs (Exception error, Token? token, phase: Symbol) -> Diagnostic
      def diagnostic_from(error, token, phase:)
        matching = @tokens.find { |candidate| error.message.start_with?("#{candidate.location}:") }
        token = matching || token || @tokens.last
        location = token&.location || Location.new(file: "(grammar)", line: 1, column: 1)
        prefix = "#{location}: "
        message = error.message.delete_prefix(prefix)
        expected, received = expected_and_received(message)
        Diagnostic.new(code: "frontend.#{phase}_error", phase: phase, message: message,
                       location: location, span: token&.span, expected: expected,
                       received: received, rendered: error.message)
      end

      # @rbs (String message) -> [Array[String], String?]
      def expected_and_received(message)
        match = message.match(/\Aexpected (.+), got (.+)\z/)
        return [[], nil] unless match

        expected = match[1]
        received = match[2]
        [expected ? [expected] : [], received]
      end
    end
  end
end
