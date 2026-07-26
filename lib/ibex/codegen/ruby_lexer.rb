# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Codegen
    # Generated lexer tables and action methods.
    module RubyLexer
      private

      # @rbs (Array[String] lines) -> void
      def append_lexer(lines)
        # @type self: Ruby
        lexer = @grammar.lexer
        return unless lexer

        lines << "  include Ibex::Runtime::GeneratedLexer"
        lines << "  LEXER_STATES = #{lexer.states.inspect}.freeze"
        append_lexer_rules(lines, lexer)
        append_lexer_actions(lines, lexer)
      end

      # @rbs (Array[String] lines, IR::Lexer lexer) -> void
      def append_lexer_rules(lines, lexer)
        # @type self: Ruby
        by_state = lexer.states.to_h do |state|
          rules = lexer.rules.select { |rule| rule.state == state }.map { |rule| lexer_rule_literal(rule) }
          [state.to_sym, "[#{rules.join(', ')}].freeze"]
        end
        source = by_state.map { |state, rules| "#{state.inspect} => #{rules}" }.join(", ")
        lines << "  LEXER_RULES_BY_STATE = { #{source} }.freeze"
        lines << ""
      end

      # @rbs (IR::LexerRule rule) -> String
      def lexer_rule_literal(rule)
        # @type self: Ruby
        flags = 0
        flags |= Regexp::IGNORECASE if rule.options.include?("i")
        flags |= Regexp::MULTILINE if rule.options.include?("m")
        flags |= Regexp::EXTENDED if rule.options.include?("x")
        action = rule.action ? ":_ibex_lexer_action_#{rule.id}" : "nil"
        terminal = rule.token && @grammar.symbol(rule.token)
        token = terminal ? external_token_expression(terminal) : "nil"
        regexp = "Regexp.new(#{"\\A(?:#{rule.pattern})".dump}, #{flags}).freeze"
        "{ id: #{rule.id}, kind: #{rule.kind.inspect}, token: #{token}, " \
          "regexp: #{regexp}, action: #{action} }.freeze"
      end

      # @rbs (Array[String] lines, IR::Lexer lexer) -> void
      def append_lexer_actions(lines, lexer)
        # @type self: Ruby
        lexer.rules.each do |rule|
          next unless rule.action

          source = lexer_action_source(rule)
          if @line_convert
            location = rule.location
            lines << "  class_eval(#{source.dump}, #{location[:file].inspect}, #{location[:line]})"
          else
            source.lines.each { |line| lines << "  #{line.rstrip}" }
          end
          lines << ""
        end
      end

      # @rbs (IR::LexerRule rule) -> String
      def lexer_action_source(rule)
        action = rule.action || ""
        binding = nil #: String?
        if (match = action.match(/\A\s*\|([a-z_][a-zA-Z0-9_]*)\|\s*(.*)\z/m))
          parameter = match[1] || "s"
          binding = "#{parameter} = _ibex_lexeme"
          action = match[2] || ""
        end
        lines = ["private def _ibex_lexer_action_#{rule.id}(_ibex_lexeme)"]
        lines << "  #{binding}" if binding
        lines << "  #{action}"
        lines << "end"
        "#{lines.join("\n")}\n"
      end
    end
  end
end
