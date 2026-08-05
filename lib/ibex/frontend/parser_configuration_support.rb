# frozen_string_literal: true

module Ibex
  module Frontend
    # Shares the closed parser-declaration semantics between bootstrap and generated frontends.
    module ParserConfigurationSupport
      # @rbs!
      #   private def token_string: (Token) -> String
      #   private def fail_at: (Location, String) -> bot
      #   private def extended_only!: (Location, String) -> void

      PARSER_SETTING_VALUES = {
        "algorithm" => %w[slr lalr ielr lr1].freeze,
        "entries" => %w[shared isolated].freeze
      }.freeze #: Hash[String, Array[String]]

      private

      # @rbs (Token key, Token value) -> AST::ParserSetting
      def build_parser_setting(key, value)
        name = token_string(key)
        admitted = PARSER_SETTING_VALUES[name]
        fail_at(key.location, "unknown parser setting #{name}") unless admitted

        selected = token_string(value)
        unless admitted.include?(selected)
          fail_at(value.location, "parser.#{name} must be one of #{admitted.join(', ')}; got #{selected}")
        end

        AST::ParserSetting.new(key: name.to_sym, value: selected.to_sym, loc: key.location)
      end

      # @rbs (Token keyword, Array[AST::ParserSetting] settings) -> AST::ParserConfiguration
      def build_parser_configuration(keyword, settings)
        extended_only!(keyword.location, "parser declarations")
        seen = {} #: Hash[Symbol, bool]
        settings.each do |setting|
          fail_at(setting.loc, "duplicate parser setting #{setting.key}") if seen[setting.key]

          seen[setting.key] = true
        end
        fail_at(keyword.location, "parser declaration requires at least one setting") if settings.empty?

        AST::ParserConfiguration.new(settings: settings, loc: keyword.location)
      end

      # @rbs (Array[AST::declaration] declarations) -> void
      def validate_root_parser_configuration(declarations)
        configurations = declarations.grep(AST::ParserConfiguration)
        duplicate = configurations.fetch(1, nil)
        fail_at(duplicate.loc, "duplicate parser declaration") if duplicate
      end
    end
  end
end
