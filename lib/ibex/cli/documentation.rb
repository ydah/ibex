# frozen_string_literal: true

require "optparse"
require_relative "../frontend"
require_relative "../normalize"
require_relative "../codegen/documentation"

module Ibex
  # Generates standalone grammar documentation from the canonical include closure.
  module CLIDocumentation
    # @rbs!
    #   type documentation_settings = {
    #     format: String,
    #     mode: Symbol,
    #     configuration_explicit: Array[Symbol],
    #     ?output: String,
    #     ?help: bool
    #   }
    #
    #   private def input_path: (Array[String]) -> String
    #   private def same_file_target?: (String left, String right) -> bool
    #   private def atomic_write_ir: (String path, String source) -> void
    #   private def local_configuration_value: (Hash[Symbol, untyped], String) -> untyped
    #   private def set_local_configuration_option: (Hash[Symbol, untyped], Symbol, untyped) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_documentation_command(arguments)
      settings = {
        format: "markdown", mode: Configuration::Registry.fetch("grammar.mode").default,
        configuration_explicit: []
      } #: documentation_settings
      parser = documentation_option_parser(settings)
      remaining = parser.parse(arguments)
      settings[:mode] = local_configuration_value(settings, "grammar.mode")
      if settings[:help]
        @stdout.puts(parser)
        return 0
      end

      path = input_path(remaining)
      output = settings[:output]
      resolution = Frontend::Resolver.new(path, mode: settings.fetch(:mode)).resolve
      reject_documentation_output_collision(output, resolution.files) if output
      grammar = Normalizer.new(resolution, mode: settings.fetch(:mode)).normalize
      rendered = Codegen::Documentation.render(grammar, format: settings.fetch(:format))
      output ? atomic_write_ir(output, rendered) : @stdout.write(rendered)
      0
    end

    # @rbs (String output, Array[String] grammar_files) -> void
    def reject_documentation_output_collision(output, grammar_files)
      collision = grammar_files.find { |grammar_file| same_file_target?(grammar_file, output) }
      return unless collision

      raise Ibex::Error,
            "(cli):1:1: doc input and output paths must be distinct; output aliases grammar source #{collision}"
    end

    # @rbs (documentation_settings settings) -> OptionParser
    def documentation_option_parser(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex doc [options] grammarfile"
        options.on("--format=FORMAT", Codegen::Documentation::FORMATS, "markdown, html, or railroad") do |value|
          settings[:format] = value
        end
        options.on("-o FILE", "--output=FILE", "write atomically to FILE") { |value| settings[:output] = value }
        options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
          set_local_configuration_option(settings, :mode, value.to_sym)
        end
        options.on("--help", "show help") { settings[:help] = true }
      end
    end
  end
end
