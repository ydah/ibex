# frozen_string_literal: true

module Ibex
  # Converts a root parser declaration into the explicit current Grammar IR contract.
  module NormalizeParserConfiguration
    private

    # @rbs (Frontend::AST::ParserConfiguration declaration) -> void
    def read_parser_configuration(declaration)
      # @type self: Normalizer
      fail_at(declaration.loc, "parser declarations require extended mode") unless @mode == :extended
      fail_at(declaration.loc, "duplicate parser declaration") if @parser_configuration

      @parser_configuration = declaration
    end

    # @rbs () -> IR::ParserContract?
    def normalized_parser_contract
      # @type self: Normalizer
      declaration = @parser_configuration
      return unless declaration

      entries = {} #: Hash[Symbol, IR::ParserContract::Entry]
      declaration.settings.each do |setting|
        validated_parser_setting_definition(setting)
        fail_at(setting.loc, "duplicate parser setting #{setting.key}") if entries.key?(setting.key)

        if setting.key == :cst_trivia && @options[:cst] != true
          fail_at(setting.loc, "parser.cst_trivia requires pragma cst")
        end

        entries[setting.key] = IR::ParserContract::Entry.new(
          setting.key, value: setting.value, location: parser_setting_location(setting), explicit: true
        )
      end
      validate_isolated_entries(declaration)
      IR::ParserContract.new(**entries)
    end

    # @rbs (Frontend::AST::ParserSetting setting) -> Hash[Symbol, Object?]
    def validated_parser_setting_definition(setting)
      # @type self: Normalizer
      definition = IR::ParserContract::DEFINITIONS[setting.key]
      fail_at(setting.loc, "unknown parser setting #{setting.key}") unless definition
      unless definition.fetch(:values).include?(setting.value)
        allowed = definition.fetch(:values).join(", ")
        fail_at(setting.loc, "parser.#{setting.key} must be one of #{allowed}; got #{setting.value}")
      end
      definition
    end

    # @rbs (Frontend::AST::ParserConfiguration declaration) -> void
    def validate_isolated_entries(declaration)
      # @type self: Normalizer
      setting = declaration.settings.find { |candidate| candidate.key == :entries && candidate.value == :isolated }
      return unless setting && @start_names.length < 2

      fail_at(setting.loc, "parser.entries isolated requires at least two start symbols")
    end

    # @rbs (Frontend::AST::ParserSetting setting) -> Location
    def parser_setting_location(setting)
      # @type self: Normalizer
      location = setting.loc
      Location.new(file: location.file, line: location.line, column: location.column)
    end
  end
end
