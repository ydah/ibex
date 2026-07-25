# frozen_string_literal: true

require "json"
require "optparse"

module Ibex
  # Batch frontend diagnostics subcommand.
  module CLIDiagnostics
    DIAGNOSTICS_SCHEMA_VERSION = 1 #: Integer
    DEFAULT_MAX_DIAGNOSTICS = 20 #: Integer

    # @rbs!
    #   type diagnostic_settings = {
    #     format: String,
    #     max_diagnostics: Integer,
    #     mode: Symbol,
    #     ?help: bool
    #   }
    #
    #   private def input_path: (Array[String]) -> String

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_diagnose_command(arguments)
      settings = {
        format: "text", max_diagnostics: DEFAULT_MAX_DIAGNOSTICS, mode: :racc
      } #: diagnostic_settings
      parser = diagnostics_option_parser(settings)
      remaining = parser.parse(arguments)
      if settings[:help]
        @stdout.puts(parser)
        return 0
      end

      path = input_path(remaining)
      result = Frontend::Parser.new(File.binread(path), file: path, mode: settings.fetch(:mode))
                               .parse_with_diagnostics(max_diagnostics: settings.fetch(:max_diagnostics))
      write_diagnostics(result, format: settings.fetch(:format))
      result.success? ? 0 : 1
    end

    # @rbs (diagnostic_settings settings) -> OptionParser
    def diagnostics_option_parser(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex diagnose [options] grammarfile"
        options.on("--format=FORMAT", %w[text json], "text or json") { |value| settings[:format] = value }
        options.on("--max-diagnostics=N", "positive diagnostic limit") do |value|
          settings[:max_diagnostics] = positive_diagnostic_limit(value)
        end
        options.on("--mode=MODE", %w[racc extended], "grammar mode") { |value| settings[:mode] = value.to_sym }
        options.on("--help", "show help") { settings[:help] = true }
      end
    end

    # @rbs (String value) -> Integer
    def positive_diagnostic_limit(value)
      limit = Integer(value, 10)
      return limit if limit.positive?

      raise OptionParser::InvalidArgument, "max diagnostics must be positive"
    rescue ArgumentError
      raise OptionParser::InvalidArgument, "max diagnostics must be a positive integer"
    end

    # @rbs (Frontend::ParseResult result, format: String) -> void
    def write_diagnostics(result, format:)
      if format == "json"
        @stdout.puts(JSON.pretty_generate(diagnostics_document(result)))
      else
        result.diagnostics.each { |diagnostic| @stdout.puts(diagnostic.to_s) }
      end
    end

    # @rbs (Frontend::ParseResult result) -> Hash[String, untyped]
    def diagnostics_document(result)
      {
        "ibex_diagnostics" => "frontend",
        "schema_version" => DIAGNOSTICS_SCHEMA_VERSION,
        "success" => result.success?,
        "ast_available" => !result.ast.nil?,
        "diagnostics" => result.diagnostics.map(&:to_h)
      }
    end
  end
end
