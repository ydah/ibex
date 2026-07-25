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
      result = resolve_diagnostic_result(result, path, settings.fetch(:mode)) if result.success?
      write_diagnostics(result, format: settings.fetch(:format))
      result.success? ? 0 : 1
    end

    # Cross-file recovery is deliberately bounded to the first resolver error.
    # @rbs (Frontend::ParseResult result, String path, Symbol mode) -> Frontend::ParseResult
    def resolve_diagnostic_result(result, path, mode)
      Frontend::Resolver.new(path, mode: mode).resolve
      result
    rescue Frontend::ResolutionIOError
      raise
    rescue Ibex::Error => e
      Frontend::ParseResult.new(diagnostics: [resolution_diagnostic(e, path)], ast: nil, document: nil)
    end

    # @rbs (Ibex::Error error, String fallback_file) -> Frontend::Diagnostic
    def resolution_diagnostic(error, fallback_file)
      match = error.message.match(/\A(.+):(\d+):(\d+): (.*)\z/m)
      location = if match
                   Frontend::Location.new(
                     file: match[1].to_s, line: Integer(match[2].to_s), column: Integer(match[3].to_s)
                   )
                 else
                   Frontend::Location.new(file: fallback_file, line: 1, column: 1)
                 end
      message = match ? match[4].to_s : error.message
      Frontend::Diagnostic.new(
        code: "frontend.resolution_error", phase: :syntax, message: message,
        location: location, rendered: error.message
      )
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
