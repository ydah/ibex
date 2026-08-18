# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../configuration/inspector"
require_relative "../frontend/source_loader"
require_relative "../frontend/resolver"
require_relative "../ir/validator"

module Ibex
  # Static effective-configuration reporting for source grammars and Grammar IR.
  module CLIConfig
    # @rbs!
    #   type config_options = {
    #     format: String,
    #     mode: Symbol,
    #     configuration_explicit: Array[Symbol],
    #     ?from: String,
    #     ?algorithm: Symbol,
    #     ?entry_isolation: bool,
    #     ?cst_trivia: Symbol,
    #     ?superclass: String,
    #     ?omit_actions: bool,
    #     ?help: String
    #   }
    #   private def input_path: (Array[String]) -> String
    #   private def set_local_configuration_option: (Hash[Symbol, Object?], Symbol, Object?) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_config_command(arguments)
      settings, paths = config_options(arguments)
      if settings[:help]
        @stdout.puts(settings.fetch(:help))
        return 0
      end

      path = input_path(paths)
      input = load_configuration_input(path, settings)
      cli_values = Configuration::CLIAdapter.new(
        settings, explicit_keys: settings.fetch(:configuration_explicit)
      ).configuration_values
      report = Configuration::Report.new(input, cli: cli_values)
      write_configuration_report(report, settings.fetch(:format))
      return 0 if report.success?

      report.conflicts.each do |conflict|
        @stderr.puts(Messages.translate("cli.error", language: @language, detail: conflict.message))
      end
      1
    end

    # @rbs (Array[String] arguments) -> [config_options, Array[String]]
    def config_options(arguments)
      settings = {
        format: "text", mode: Configuration::Registry.fetch("grammar.mode").default,
        configuration_explicit: []
      } #: config_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex config [options] grammarfile"
        add_config_options(options, settings)
      end
      [settings, parser.parse(arguments)]
    end

    # @rbs (OptionParser options, config_options settings) -> void
    def add_config_options(options, settings)
      options.on("--format=FORMAT", %w[text json], "text or json (default: text)") do |value|
        settings[:format] = value
      end
      options.on("--from=FORMAT", %w[grammar-ir], "read validated Grammar IR JSON") do |value|
        settings[:from] = value
      end
      add_config_contract_options(options, settings)
      options.on("--help", "show help") { settings[:help] = options.to_s }
    end

    # @rbs (OptionParser options, config_options settings) -> void
    def add_config_contract_options(options, settings)
      options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
        set_local_configuration_option(settings, :mode, value.to_sym)
      end
      options.on(
        "--algorithm=NAME", Configuration::Registry::CLI_ALGORITHM_VALUES, "parser construction algorithm"
      ) do |value|
        set_local_configuration_option(settings, :algorithm, value.to_sym)
      end
      options.on("--entry-isolation", "build independent state sets for each start symbol") do
        set_local_configuration_option(settings, :entry_isolation, true)
      end
      options.on("--cst-trivia=POLICY", Configuration::Registry::CLI_CST_TRIVIA_VALUES, "CST trivia policy") do |value|
        set_local_configuration_option(settings, :cst_trivia, value.to_sym)
      end
      options.on("--superclass=CLASS", "request a parser superclass") do |value|
        set_local_configuration_option(settings, :superclass, value)
      end
      options.on("--no-omit-actions", "generate implicit action methods") do
        set_local_configuration_option(settings, :omit_actions, false)
      end
    end

    # @rbs (String path, config_options settings) -> Configuration::Input
    def load_configuration_input(path, settings)
      return load_grammar_ir_configuration(path) if settings[:from] == "grammar-ir"

      loader = Frontend::SourceLoader.new(record_reads: true)
      resolver = Frontend::Resolver.new(path, mode: settings.fetch(:mode), loader: loader)
      Configuration::Inspector.from_source(resolver.resolve)
    end

    # @rbs (String path) -> Configuration::Input
    def load_grammar_ir_configuration(path)
      value = IR::Validator.validate(File.binread(path))
      raise Ibex::Error, "#{path}:1:1: expected grammar-ir input" unless value.is_a?(IR::Grammar)

      Configuration::Inspector.from_grammar_ir(value, path: path)
    end

    # @rbs (Configuration::Report report, String format) -> void
    def write_configuration_report(report, format)
      if format == "json"
        @stdout.puts(JSON.pretty_generate(report.to_h))
      else
        @stdout.write(report.render_text)
      end
    end
  end
end
