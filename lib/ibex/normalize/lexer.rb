# frozen_string_literal: true

module Ibex
  # Lexer declaration normalization and static safety checks.
  module NormalizeLexer
    private

    # @rbs () -> IR::Lexer?
    def normalize_lexer
      # @type self: Normalizer
      declaration = @lexer_declaration
      return unless declaration

      states = ["INITIAL"] #: Array[String]
      rules = [] #: Array[IR::LexerRule]
      warnings = [] #: Array[IR::lexer_warning]
      declaration.definitions.each do |definition|
        if definition.is_a?(Frontend::AST::LexerState)
          normalize_lexer_state(definition, states, rules, warnings)
        else
          rules << normalize_lexer_rule(definition, "INITIAL", rules.length, warnings)
        end
      end
      fail_at(declaration.loc, "lexer declaration requires at least one rule") if rules.empty?
      IR::Lexer.new(
        states: states, rules: rules, warnings: warnings,
        source_provenance: { file: declaration.loc.file, root: @resolution&.root_directory, byte_span: nil }
      )
    end

    # @rbs (Frontend::AST::LexerState definition, Array[String] states, Array[IR::LexerRule] rules,
    #   Array[IR::lexer_warning] warnings) -> void
    def normalize_lexer_state(definition, states, rules, warnings)
      # @type self: Normalizer
      fail_at(definition.loc, "lexer state INITIAL is reserved") if definition.name == "INITIAL"
      fail_at(definition.loc, "duplicate lexer state #{definition.name}") if states.include?(definition.name)
      states << definition.name
      definition.definitions.each do |entry|
        fail_at(entry.loc, "nested lexer states are not supported") if entry.is_a?(Frontend::AST::LexerState)

        rules << normalize_lexer_rule(entry, definition.name, rules.length, warnings)
      end
    end

    # @rbs (Frontend::AST::LexerRule definition, String state, Integer id,
    #   Array[IR::lexer_warning] warnings) -> IR::LexerRule
    def normalize_lexer_rule(definition, state, id, warnings)
      # @type self: Normalizer
      validate_lexer_token(definition)
      validate_lexer_action(definition)
      source, options = normalize_lexer_pattern(definition)
      validate_lexer_regexp(definition, source, options)
      if risky_lexer_pattern?(source)
        warning = { type: :lexer_redos, loc: definition.loc.to_h } #: IR::grammar_warning
        warning[:symbol] = definition.token if definition.token
        @warnings << warning
        warnings << { type: :redos, rule: id, loc: definition.loc.to_h }
      end
      IR::LexerRule.new(
        id: id, state: state, kind: definition.kind, token: definition.token,
        pattern: source, pattern_kind: definition.pattern_kind, options: options,
        action: definition.action, location: definition.loc.to_h
      )
    end

    # @rbs (Frontend::AST::LexerRule definition) -> void
    def validate_lexer_token(definition)
      # @type self: Normalizer
      return unless definition.kind == :token
      return if definition.token && @declared_tokens.key?(definition.token)

      fail_at(definition.loc, "lexer rule references undeclared terminal #{definition.token}")
    end

    # @rbs (Frontend::AST::LexerRule definition) -> void
    def validate_lexer_action(definition)
      # @type self: Normalizer
      action = definition.action
      return unless action&.lstrip&.start_with?("|")

      match = action.match(/\A\s*\|([a-z_][a-zA-Z0-9_]*)\|/m)
      fail_at(definition.loc, "lexer action accepts exactly one local identifier") unless match
      name = match[1]
      fail_at(definition.loc, "lexer action parameter #{name.inspect} is a Ruby keyword") if
        Normalizer::RUBY_KEYWORDS.include?(name)
    end

    # @rbs (Frontend::AST::LexerRule definition) -> [String, String]
    def normalize_lexer_pattern(definition)
      # @type self: Normalizer
      raw = definition.pattern
      if definition.pattern_kind == :literal
        decoded = decode_lexer_literal(raw, definition.loc)
        fail_at(definition.loc, "lexer pattern must not be empty") if decoded.empty?
        return [Regexp.escape(decoded), ""]
      end

      closing = raw.rindex("/")
      fail_at(definition.loc, "invalid lexer regular expression") unless closing&.positive?
      [raw[1...closing] || "", raw[(closing + 1)..] || ""]
    end

    # @rbs (String raw, Frontend::Location location) -> String
    def decode_lexer_literal(raw, location)
      # @type self: Normalizer
      return raw.undump if raw.start_with?('"')

      (raw[1...-1] || "").gsub("\\'", "'").gsub("\\\\", "\\")
    rescue RuntimeError => e
      fail_at(location, "invalid lexer literal: #{e.message}")
    end

    # @rbs (Frontend::AST::LexerRule definition, String source, String options) -> void
    def validate_lexer_regexp(definition, source, options)
      # @type self: Normalizer
      flags = 0
      flags |= Regexp::IGNORECASE if options.include?("i")
      flags |= Regexp::MULTILINE if options.include?("m")
      flags |= Regexp::EXTENDED if options.include?("x")
      regexp = Regexp.new("\\A(?:#{source})", flags)
      fail_at(definition.loc, "lexer pattern must not match an empty string") if regexp.match?("")
    rescue RegexpError => e
      fail_at(definition.loc, "invalid lexer regular expression: #{e.message}")
    end

    # @rbs (String source) -> bool
    def risky_lexer_pattern?(source)
      source.match?(/\([^)]*[+*][^)]*\)[+*{]/) || source.match?(/\.\*[+*{]/)
    end
  end
end
