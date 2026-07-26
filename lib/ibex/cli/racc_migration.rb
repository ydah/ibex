# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require "optparse"

module Ibex
  # Static racc migration checks and differential harness generation.
  module CLIRaccMigration
    # @rbs!
    #   type migration_check_settings = {
    #     format: String,
    #     ?help: bool
    #   }
    #   type migration_harness_settings = {
    #     ?output: String,
    #     ?help: bool
    #   }
    #
    #   private def input_path: (Array[String]) -> String
    #   private def atomic_write_ir: (String path, String source) -> void
    #   private def same_file_target?: (String left, String right) -> bool

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_migrate_check_command(arguments)
      settings = { format: "text" } #: migration_check_settings
      parser = migrate_check_options(settings)
      paths = parser.parse(arguments)
      if settings[:help]
        @stdout.puts(parser)
        return 0
      end

      path = input_path(paths)
      report = RaccMigration::Checker.new.check(File.binread(path), file: path)
      @stdout.write(settings.fetch(:format) == "json" ? "#{report.to_json}\n" : report.to_text)
      report.compatible? ? 0 : 1
    end

    # @rbs (Array[String] arguments) -> Integer
    def run_migrate_harness_command(arguments)
      settings = {} #: migration_harness_settings
      parser = migrate_harness_options(settings)
      paths = parser.parse(arguments)
      if settings[:help]
        @stdout.puts(parser)
        return 0
      end

      path = input_path(paths)
      report = RaccMigration::Checker.new.check(File.binread(path), file: path)
      unless report.compatible? && report.class_name
        raise Ibex::Error, "(migration):1:1: grammar must pass migrate-check before harness generation"
      end

      source = RaccMigration::Harness.generate(report.class_name)
      output = settings[:output]
      if output && same_file_target?(path, output)
        raise Ibex::Error, "(migration):1:1: grammar and harness output paths must be distinct"
      end

      output ? atomic_write_ir(output, source) : @stdout.write(source)
      0
    end

    # @rbs (migration_check_settings settings) -> OptionParser
    def migrate_check_options(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex migrate-check [--format=text|json] grammarfile"
        options.on("--format=FORMAT", %w[text json], "text or json") { |value| settings[:format] = value }
        options.on("--help", "show help") { settings[:help] = true }
      end
    end

    # @rbs (migration_harness_settings settings) -> OptionParser
    def migrate_harness_options(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex migrate-harness [-o FILE] grammarfile"
        options.on("-o FILE", "--output=FILE", "write the harness atomically") { |value| settings[:output] = value }
        options.on("--help", "show help") { settings[:help] = true }
      end
    end
  end
end
