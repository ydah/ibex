# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"
require_relative "../bison_import"

module Ibex
  # CLI boundary for analysis-only Bison grammar import.
  module CLIBisonImport
    # @rbs!
    #   type bison_import_options = {
    #     format: String,
    #     max_bytes: Integer,
    #     max_tokens: Integer,
    #     max_rules: Integer,
    #     max_actions: Integer,
    #     ?output: String,
    #     ?class_name: String,
    #     ?help: bool
    #   }
    #   private def same_file_target?: (String, String) -> bool
    #   private def atomic_write_ir: (String, String) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_bison_import_command(arguments)
      kind = arguments.shift
      raise Ibex::Error, "(bison-import):1:1: import requires the `bison` format" unless kind == "bison"

      settings = default_bison_import_options
      parser = bison_import_option_parser(settings)
      paths = parser.parse(arguments)
      if settings[:help]
        @stdout.puts(parser)
        return 0
      end
      raise Ibex::Error, "(bison-import):1:1: import bison requires exactly one source file" unless paths.length == 1

      path = paths.fetch(0)
      result = build_bison_import(path, settings)
      rendered = settings.fetch(:format) == "json" ? "#{JSON.pretty_generate(result.to_h)}\n" : result.source
      write_bison_import(path, settings[:output], rendered)
      0
    rescue BisonImport::BudgetExceeded => e
      @stdout.puts(JSON.pretty_generate({ ibex_report: "bison_import", schema_version: 1 }.merge(e.details)))
      2
    end

    # @rbs () -> bison_import_options
    def default_bison_import_options
      {
        format: "source",
        max_bytes: BisonImport::Importer::DEFAULT_MAX_BYTES,
        max_tokens: BisonImport::Importer::DEFAULT_MAX_TOKENS,
        max_rules: BisonImport::Importer::DEFAULT_MAX_RULES,
        max_actions: BisonImport::Importer::DEFAULT_MAX_ACTIONS
      }
    end

    # @rbs (bison_import_options settings) -> OptionParser
    def bison_import_option_parser(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex import bison [options] grammar.y"
        options.on("--format=FORMAT", %w[source json], "converted source or JSON report") do |value|
          settings[:format] = value
        end
        options.on("-o FILE", "--output=FILE", "write atomically to FILE") { |value| settings[:output] = value }
        options.on("--class=NAME", "generated analysis grammar class") { |value| settings[:class_name] = value }
        add_bison_import_budgets(options, settings)
        options.on("--help", "show help") { settings[:help] = true }
      end
    end

    # @rbs (OptionParser options, bison_import_options settings) -> void
    def add_bison_import_budgets(options, settings)
      {
        "max-bytes" => :max_bytes,
        "max-tokens" => :max_tokens,
        "max-rules" => :max_rules,
        "max-actions" => :max_actions
      }.each do |name, key|
        options.on("--#{name}=N", Integer, "positive import budget") do |value|
          raise OptionParser::InvalidArgument, "--#{name} must be positive" unless value.positive?

          settings[key] = value
        end
      end
    end

    # @rbs (String path, bison_import_options settings) -> BisonImport::Result
    def build_bison_import(path, settings)
      BisonImport::Importer.new(
        File.binread(path),
        file: path,
        class_name: settings[:class_name],
        max_bytes: settings.fetch(:max_bytes),
        max_tokens: settings.fetch(:max_tokens),
        max_rules: settings.fetch(:max_rules),
        max_actions: settings.fetch(:max_actions)
      ).run
    end

    # @rbs (String input, String? output, String source) -> void
    def write_bison_import(input, output, source)
      unless output
        @stdout.write(source)
        return
      end
      if same_file_target?(input, output)
        raise Ibex::Error, "(bison-import):1:1: import input and output paths must be distinct"
      end
      if File.symlink?(output) || (File.exist?(output) && File.stat(output).nlink > 1)
        raise Ibex::Error, "(bison-import):1:1: output refuses symlink aliases and files with multiple hard links"
      end

      atomic_write_ir(output, source)
    end
  end
end
