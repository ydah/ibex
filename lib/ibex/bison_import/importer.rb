# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module BisonImport
    # Converts Bison declarations and productions into analysis-only Ibex
    # source without parsing or executing C.
    # rubocop:disable Metrics/ClassLength -- declaration and rule recovery share one positioned directive report.
    class Importer
      # @rbs!
      #   type alternative = { items: Array[String], precedence: String? }
      #   type rule = { lhs: String, alternatives: Array[alternative] }

      DEFAULT_MAX_BYTES = 20 * 1024 * 1024 #: Integer
      DEFAULT_MAX_TOKENS = 1_000_000 #: Integer
      DEFAULT_MAX_RULES = 50_000 #: Integer
      DEFAULT_MAX_ACTIONS = 100_000 #: Integer

      # @rbs (String source, file: String, ?class_name: String?, ?max_bytes: Integer,
      #   ?max_tokens: Integer, ?max_rules: Integer, ?max_actions: Integer) -> void
      def initialize(source, file:, class_name: nil, max_bytes: DEFAULT_MAX_BYTES,
                     max_tokens: DEFAULT_MAX_TOKENS, max_rules: DEFAULT_MAX_RULES,
                     max_actions: DEFAULT_MAX_ACTIONS)
        @source = source
        @file = file
        @class_name = class_name
        @max_bytes = positive_limit(max_bytes, :max_bytes)
        @max_tokens = positive_limit(max_tokens, :max_tokens)
        @max_rules = positive_limit(max_rules, :max_rules)
        @max_actions = positive_limit(max_actions, :max_actions)
        @directives = [] #: Array[Directive]
        @actions = [] #: Array[Action]
        @token_entries = [] #: Array[[String, String?]]
        @terminal_names = {} #: Hash[String, String]
        @nonterminal_names = {} #: Hash[String, String]
        @precedence_levels = [] #: Array[[String, Array[String]]]
        @starts = [] #: Array[String]
        @expected_sr = nil #: Integer?
        @expected_rr = nil #: Integer?
      end

      # @rbs () -> Result
      def run
        validate_source
        declarations, grammar, grammar_line = split_sections
        parse_declarations(declarations)
        tokens = Tokenizer.new(grammar, start_line: grammar_line, max_tokens: @max_tokens).tokenize
        register_nonterminals(tokens)
        rules = parse_rules(tokens)
        source = render_source(rules)
        Result.new(
          source: source, file: @file, class_name: resolved_class_name,
          directives: @directives, actions: @actions, rule_count: rules.length,
          bounds: bounds
        )
      end

      private

      # @rbs () -> void
      def validate_source
        source = @source #: String
        if source.bytesize > @max_bytes
          raise BudgetExceeded.new(
            result: "budget_exhausted", phase: "input_bytes",
            observed_bytes: source.bytesize, max_bytes: @max_bytes
          )
        end
        raise Ibex::Error, "#{@file}:1:1: Bison grammar must be valid UTF-8" unless source.valid_encoding?
      end

      # @rbs () -> [String, String, Integer]
      def split_sections
        source = @source #: String
        lines = source.lines
        markers = [] #: Array[Integer]
        percent_code = false
        lines.each_with_index do |line, index|
          percent_code = true if line.match?(/^\s*%\{/)
          markers << index if !percent_code && line.match?(%r{^\s*%%(?:\s|/|$)})
          percent_code = false if percent_code && line.match?(/%\}\s*$/)
          break if markers.length == 2
        end
        raise Ibex::Error, "#{@file}:1:1: expected two Bison %% section markers" if markers.length < 2

        first = markers.fetch(0)
        second = markers.fetch(1)
        header_lines = lines[0...first] #: Array[String]
        grammar_lines = lines[(first + 1)...second] #: Array[String]
        [header_lines.join, grammar_lines.join, first + 2]
      end

      # @rbs (String source) -> void
      def parse_declarations(source)
        chunks = declaration_chunks(source)
        chunks.each do |chunk|
          name = chunk.fetch(:name)
          detail = chunk.fetch(:detail)
          record_directive(name, chunk.fetch(:line), chunk.fetch(:column), detail)
          case name
          when "token" then parse_token_declaration(detail)
          when "left", "right", "nonassoc", "precedence" then parse_precedence(name, detail)
          when "start" then parse_start(detail)
          when "expect" then @expected_sr = first_integer(detail)
          when "expect-rr" then @expected_rr = first_integer(detail)
          end
        end
      end

      # @rbs (String source) -> Array[{ name: String, detail: String, line: Integer, column: Integer }]
      def declaration_chunks(source)
        chunks = [] #: Array[{ name: String, detail: String, line: Integer, column: Integer }]
        current = nil #: { name: String, detail: String, line: Integer, column: Integer }?
        in_percent_code = false
        source.lines.each_with_index do |line, index|
          if line.match?(/^\s*%\{/)
            in_percent_code = true
            next
          end
          if in_percent_code
            in_percent_code = false if line.match?(/%\}\s*$/)
            next
          end

          match = line.match(/^(\s*)%([A-Za-z][A-Za-z0-9_-]*)(.*)$/)
          if match
            chunks << current if current
            current = {
              name: match[2].to_s,
              detail: match[3].to_s,
              line: index + 1,
              column: match[1].to_s.bytesize + 1
            }
          elsif current
            current[:detail] = "#{current.fetch(:detail)}\n#{line}"
          end
        end
        chunks << current if current
        chunks
      end

      # @rbs (String detail) -> void
      def parse_token_declaration(detail)
        token_entries = @token_entries #: Array[[String, String?]]
        current = nil #: String?
        declaration_atoms(detail).each do |atom|
          if identifier_atom?(atom)
            token_entries << [current, nil] if current
            current = atom
            terminal_name(atom)
          elsif current && atom.start_with?('"')
            token_entries << [current, atom]
            current = nil
          end
        end
        token_entries << [current, nil] if current
      end

      # @rbs (String association, String detail) -> void
      def parse_precedence(association, detail)
        symbols = declaration_atoms(detail).select { |atom| identifier_atom?(atom) || literal_atom?(atom) }
        precedence_levels = @precedence_levels #: Array[[String, Array[String]]]
        precedence_levels << [association == "precedence" ? "%precedence" : association, symbols] unless symbols.empty?
      end

      # @rbs (String detail) -> void
      def parse_start(detail)
        symbol = declaration_atoms(detail).find { |atom| identifier_atom?(atom) }
        starts = @starts #: Array[String]
        starts << symbol if symbol
      end

      # @rbs (Array[Tokenizer::Token] tokens) -> Array[rule]
      def parse_rules(tokens)
        rules = [] #: Array[rule]
        cursor = 0
        while cursor < tokens.length
          definition = next_lhs(tokens, cursor)
          break unless definition

          lhs_index, colon_index = definition
          lhs = nonterminal_name(tokens.fetch(lhs_index).value)
          cursor = colon_index + 1
          alternatives, cursor = parse_alternatives(tokens, cursor)
          rules << { lhs: lhs, alternatives: alternatives }
          check_rule_budget(rules.length)
        end
        raise Ibex::Error, "#{@file}:1:1: Bison grammar section contains no productions" if rules.empty?

        rules
      end

      # @rbs (Array[Tokenizer::Token] tokens) -> void
      def register_nonterminals(tokens)
        cursor = 0
        while (definition = next_lhs(tokens, cursor))
          lhs_index, colon_index = definition
          nonterminal_name(tokens.fetch(lhs_index).value)
          cursor = colon_index + 1
        end
      end

      # @rbs (Array[Tokenizer::Token] tokens, Integer cursor) -> [Integer, Integer]?
      def next_lhs(tokens, cursor)
        while cursor < tokens.length
          definition = lhs_definition_at(tokens, cursor)
          return definition if definition

          cursor += 1
        end
      end

      # Bison permits a named reference between an LHS and its colon:
      # `expression[result]: ...`.
      # @rbs (Array[Tokenizer::Token] tokens, Integer cursor) -> [Integer, Integer]?
      def lhs_definition_at(tokens, cursor)
        return unless tokens[cursor]&.type == :symbol

        colon = cursor + 1
        colon += 1 while tokens[colon]&.type == :tag
        [cursor, colon] if tokens[colon]&.type == :colon
      end

      # @rbs (Array[Tokenizer::Token] tokens, Integer cursor) -> [Array[alternative], Integer]
      def parse_alternatives(tokens, cursor)
        alternatives = [] #: Array[alternative]
        current = { items: [], precedence: nil } #: alternative
        while cursor < tokens.length
          token = tokens.fetch(cursor)
          if lhs_definition_at(tokens, cursor)
            alternatives << current
            return [alternatives, cursor]
          end

          case token.type
          when :pipe
            alternatives << current
            current = { items: [], precedence: nil }
          when :semicolon
            alternatives << current
            return [alternatives, cursor + 1]
          when :symbol, :literal
            current.fetch(:items) << render_symbol(token)
          when :action
            current.fetch(:items) << render_action(token)
          when :directive
            cursor = consume_rule_directive(tokens, cursor, current)
          end
          cursor += 1
        end
        alternatives << current
        [alternatives, cursor]
      end

      # @rbs (Array[Tokenizer::Token] tokens, Integer cursor, alternative alternative) -> Integer
      def consume_rule_directive(tokens, cursor, alternative)
        token = tokens.fetch(cursor)
        name = token.value.delete_prefix("%")
        record_directive(name, token.line, token.column, token.value)
        return cursor if name == "empty"

        if name == "prec"
          following = tokens[cursor + 1]
          if following && %i[symbol literal].include?(following.type)
            alternative[:precedence] =
              following.type == :literal ? following.value : terminal_name(following.value)
            return cursor + 1
          end
          raise Ibex::Error, "#{@file}:#{token.line}:#{token.column}: %prec requires a symbol"
        end

        return cursor + 1 if %w[dprec merge].include?(name) && tokens[cursor + 1]

        cursor
      end

      # @rbs (Tokenizer::Token token) -> String
      def render_symbol(token)
        return token.value if token.type == :literal

        nonterminal_names = @nonterminal_names #: Hash[String, String]
        nonterminal_names.fetch(token.value) { terminal_name(token.value) }
      end

      # @rbs (Tokenizer::Token token) -> String
      def render_action(token)
        actions = @actions #: Array[Action]
        check_action_budget(actions.length + 1, token)
        transformed = transform_action(token.value)
        encoded = transformed.unpack1("H*").to_s
        action = Action.new(
          id: actions.length + 1, line: token.line, column: token.column,
          original: token.value, transformed: transformed, encoded: encoded
        )
        actions << action
        "{ #{FOREIGN_ACTION_SENTINEL}(#{encoded.inspect}) }"
      end

      # @rbs (String code) -> String
      def transform_action(code)
        transformed = code.gsub(/\$<[^>]+>\$/, "result")
        transformed = transformed.gsub(/\$<[^>]+>(\d+)/) { "val[#{::Regexp.last_match(1).to_i - 1}]" }
        transformed = transformed.gsub("$$", "result")
        transformed = transformed.gsub(/\$(\d+)/) { "val[#{::Regexp.last_match(1).to_i - 1}]" }
        transformed = transformed.gsub(/@<[^>]+>(\d+)/, '@\1')
        transformed.gsub(/@\$/, "result_loc")
      end

      # @rbs (Array[rule] rules) -> String
      def render_source(rules)
        directives = @directives #: Array[Directive]
        token_entries = @token_entries #: Array[[String, String?]]
        starts = @starts #: Array[String]
        lines = [
          "# Imported from #{@file} for analysis only.",
          "# C actions are opaque; Ruby parser generation is intentionally refused.",
          "# #{STRUCTURAL_STATUS_MARKER}: #{structural_status}"
        ]
        directives.select { |directive| directive.status == :unsupported }.each do |directive|
          lines << "# unsupported %#{directive.name} at #{directive.line}:#{directive.column}"
        end
        lines.push("class #{resolved_class_name}", "pragma extended")
        token_entries.uniq.sort.each do |name, alias_name|
          rendered = "token #{terminal_name(name)}"
          rendered = "#{rendered} #{alias_name}" if alias_name
          lines << rendered
        end
        render_precedence(lines)
        lines << "expect #{@expected_sr}" if @expected_sr
        lines << "%expect-rr #{@expected_rr}" if @expected_rr
        lines << "start #{starts.uniq.map { |name| nonterminal_name(name) }.join(' ')}" unless starts.empty?
        lines << "rule"
        rules.each { |rule| render_rule(lines, rule) }
        lines << "end"
        "#{lines.join("\n")}\n"
      end

      # @rbs () -> String
      def structural_status
        directives = @directives #: Array[Directive]
        unsupported = directives.select do |directive|
          directive.status == :unsupported &&
            !STRUCTURE_NEUTRAL_UNSUPPORTED.include?(directive.name)
        end
        unsupported.empty? ? "complete" : "incomplete"
      end

      # @rbs (Array[String] lines) -> void
      def render_precedence(lines)
        precedence_levels = @precedence_levels #: Array[[String, Array[String]]]
        return if precedence_levels.empty?

        lines << "preclow"
        precedence_levels.each do |association, symbols|
          rendered = symbols.map { |symbol| literal_atom?(symbol) ? symbol : terminal_name(symbol) }
          lines << "  #{association} #{rendered.join(' ')}"
        end
        lines << "prechigh"
      end

      # @rbs (Array[String] lines, rule rule) -> void
      def render_rule(lines, rule)
        alternatives = rule.fetch(:alternatives)
        alternatives.each_with_index do |alternative, index|
          prefix = index.zero? ? "#{rule.fetch(:lhs)}:" : "  |"
          items = alternative.fetch(:items)
          suffix = alternative[:precedence] ? " = #{alternative.fetch(:precedence)}" : ""
          lines << "#{prefix} #{items.join(' ')}#{suffix}".rstrip
        end
      end

      # @rbs (String name, Integer line, Integer column, String detail) -> void
      def record_directive(name, line, column, detail)
        status = DIRECTIVES.fetch(name, :unsupported)
        directives = @directives #: Array[Directive]
        directives << Directive.new(
          name: name, status: status, line: line, column: column, detail: detail.strip
        )
      end

      # @rbs (String detail) -> Array[String]
      def declaration_atoms(detail)
        source = strip_declaration_comments(detail)
        source = source.gsub(/\b[A-Z][A-Z0-9_]*\([^()\n]*\)/, " ")
        source.scan(
          /<[^>]*>|"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[A-Za-z_$][A-Za-z0-9_$.-]*|\d+/
        ).map(&:to_s)
      end

      # @rbs (String source) -> String
      def strip_declaration_comments(source)
        pattern = %r{("(?:\\.|[^"])*"|'(?:\\.|[^'])*')|/\*.*?\*/|//[^\n]*|^[ \t]*\#[^\n]*}m
        source.gsub(pattern) do |match|
          match.start_with?('"', "'") ? match : " "
        end
      end

      # @rbs (String value) -> bool
      def identifier_atom?(value)
        value.match?(/\A[A-Za-z_$][A-Za-z0-9_$.-]*\z/)
      end

      # @rbs (String value) -> bool
      def literal_atom?(value)
        value.start_with?('"', "'")
      end

      # @rbs (String value) -> String
      def sanitize_symbol(value)
        sanitized = value.gsub(/[^A-Za-z0-9_]/, "_")
        sanitized = "_#{sanitized}" if sanitized.match?(/\A\d/)
        sanitized.empty? ? "_bison_symbol" : sanitized
      end

      # @rbs (String value) -> String
      def terminal_name(value)
        return "error" if value == "error"

        terminal_names = @terminal_names #: Hash[String, String]
        terminal_names[value] ||= begin
          sanitized = sanitize_symbol(value)
          base = if sanitized.match?(/\A[A-Z][A-Z0-9_]*\z/)
                   sanitized
                 else
                   "BISON_T_#{sanitized.upcase}"
                 end
          used = terminal_names.values
          candidate = base
          suffix = 2
          while used.include?(candidate)
            candidate = "#{base}_#{suffix}"
            suffix += 1
          end
          candidate
        end
      end

      # All imported nonterminals receive a lowercase namespace. This avoids
      # Ibex's terminal-by-case convention and declaration keyword collisions.
      # @rbs (String value) -> String
      def nonterminal_name(value)
        nonterminal_names = @nonterminal_names #: Hash[String, String]
        nonterminal_names[value] ||= begin
          base = "bison_nt_#{sanitize_symbol(value).downcase}"
          used = nonterminal_names.values
          candidate = base
          suffix = 2
          while used.include?(candidate)
            candidate = "#{base}_#{suffix}"
            suffix += 1
          end
          candidate
        end
      end

      # @rbs () -> String
      def resolved_class_name
        return sanitize_class_name(@class_name) if @class_name

        stem = File.basename(@file).sub(/\.[^.]+\z/, "")
        "Imported#{sanitize_class_name(stem)}Parser"
      end

      # @rbs (String value) -> String
      def sanitize_class_name(value)
        parts = value.scan(/[A-Za-z0-9]+/).map(&:to_s)
        rendered = parts.map { |part| part.sub(/\A./, &:upcase) }.join
        rendered = "Grammar" if rendered.empty?
        rendered = "Grammar#{rendered}" if rendered.match?(/\A\d/)
        rendered
      end

      # @rbs (String value) -> Integer?
      def first_integer(value)
        match = value.match(/\d+/)
        match ? Integer(match[0], 10) : nil
      end

      # @rbs (Integer count) -> void
      def check_rule_budget(count)
        return if count <= @max_rules

        raise BudgetExceeded.new(
          result: "budget_exhausted", phase: "rules",
          observed_rules: count, max_rules: @max_rules
        )
      end

      # @rbs (Integer count, Tokenizer::Token token) -> void
      def check_action_budget(count, token)
        return if count <= @max_actions

        raise BudgetExceeded.new(
          result: "budget_exhausted", phase: "actions", line: token.line,
          observed_actions: count, max_actions: @max_actions
        )
      end

      # @rbs (Integer value, Symbol name) -> Integer
      def positive_limit(value, name)
        return value if value.positive?

        raise ArgumentError, "#{name} must be positive"
      end

      # @rbs () -> Hash[Symbol, Integer]
      def bounds
        {
          max_bytes: @max_bytes, max_tokens: @max_tokens,
          max_rules: @max_rules, max_actions: @max_actions
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
