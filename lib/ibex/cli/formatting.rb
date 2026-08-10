# frozen_string_literal: true

require "tempfile"
require "optparse"
require_relative "../frontend"

module Ibex
  # CLI coordination for deterministic, semantics-preserving grammar formatting.
  # rubocop:disable Metrics/ModuleLength -- transaction lifecycle stays cohesive and auditable.
  module CLIFormatting
    # @rbs!
    #   type formatting_settings = {
    #     paths: Array[String],
    #     mode: Symbol,
    #     check: bool,
    #     write: bool,
    #     configuration_explicit: Array[Symbol],
    #     ?stdin_filename: String,
    #     ?help: bool
    #   }
    #   type formatting_result = {
    #     path: String,
    #     label: String,
    #     source: String,
    #     formatted: String
    #   }
    #   type formatting_target = {
    #     path: String,
    #     label: String,
    #     target: String,
    #     formatted: String,
    #     mode: Integer,
    #     directory: String,
    #     basename: String,
    #     changed: bool,
    #     installed: bool,
    #     ?stage: String,
    #     ?backup: String
    #   }
    #   type formatting_cleanup_result = {
    #     errors: Array[String],
    #     remaining: Array[String]
    #   }
    #   private def local_configuration_value: (Hash[Symbol, Object?], String) -> Object?
    #   private def set_local_configuration_option: (Hash[Symbol, Object?], Symbol, Object?) -> void

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_format_command(arguments)
      settings = formatting_options(arguments)
      if settings[:help]
        @stdout.puts(formatting_option_parser(settings))
        return 0
      end

      validate_formatting_settings!(settings)
      results, failed = prepare_formatting_results(settings)
      if settings.fetch(:check)
        check_status = check_formatting_results(results)
        return 1 if failed

        return check_status
      end
      return 1 if failed
      return write_formatting_results(results) if settings.fetch(:write)

      @stdout.write(results.fetch(0).fetch(:formatted))
      0
    end

    # @rbs (Array[String] arguments) -> formatting_settings
    def formatting_options(arguments)
      settings = {
        paths: [], mode: Configuration::Registry.fetch("grammar.mode").default, check: false, write: false,
        configuration_explicit: []
      } #: formatting_settings
      settings[:paths] = formatting_option_parser(settings).parse(arguments)
      settings[:mode] = local_configuration_value(settings, "grammar.mode")
      settings
    end

    # @rbs (formatting_settings settings) -> OptionParser
    def formatting_option_parser(settings)
      OptionParser.new do |options|
        options.banner = "Usage: ibex fmt [--check | --write] [options] grammar.y [...]"
        options.on("--check", "report files that need formatting") { settings[:check] = true }
        options.on("--write", "atomically format files in place") { settings[:write] = true }
        options.on("--mode=MODE", %w[default extended], "grammar mode") do |value|
          set_local_configuration_option(settings, :mode, value.to_sym)
        end
        options.on("--stdin-filename=FILE", "diagnostic filename for standard input") do |value|
          settings[:stdin_filename] = value
        end
        options.on("--help", "show help") { settings[:help] = true }
      end
    end

    # @rbs (formatting_settings settings) -> void
    def validate_formatting_settings!(settings)
      paths = settings.fetch(:paths)
      raise Ibex::Error, "(cli):1:1: fmt requires at least one grammar file" if paths.empty?

      validate_formatting_operation!(settings, paths)
      validate_formatting_stdin!(settings, paths)
    end

    # @rbs (formatting_settings settings, Array[String] paths) -> void
    def validate_formatting_operation!(settings, paths)
      if settings.fetch(:check) && settings.fetch(:write)
        raise Ibex::Error, "(cli):1:1: fmt --check and --write cannot be combined"
      end
      return if settings.fetch(:check) || settings.fetch(:write) || paths.length == 1

      raise Ibex::Error, "(cli):1:1: fmt writes to stdout only for exactly one input"
    end

    # @rbs (formatting_settings settings, Array[String] paths) -> void
    def validate_formatting_stdin!(settings, paths)
      raise Ibex::Error, "(cli):1:1: fmt standard input may be specified only once" if paths.count("-") > 1

      if paths.include?("-") && (settings.fetch(:check) || settings.fetch(:write))
        raise Ibex::Error, "(cli):1:1: fmt --check and --write require file inputs"
      end
      if settings[:stdin_filename] && formatting_control_bytes?(settings.fetch(:stdin_filename))
        raise Ibex::Error, "(cli):1:1: --stdin-filename must not contain control characters"
      end
      return unless settings[:stdin_filename] && paths != ["-"]

      raise Ibex::Error, "(cli):1:1: --stdin-filename requires fmt -"
    end

    # @rbs (formatting_settings settings) -> [Array[formatting_result], bool]
    def prepare_formatting_results(settings)
      failed = false
      results = [] #: Array[formatting_result]
      settings.fetch(:paths).each do |path|
        source = path == "-" ? @stdin.read : File.binread(path)
        label = path == "-" ? settings[:stdin_filename] || "(stdin)" : formatting_label(path)
        formatted = Frontend::Formatter.format(source, file: label, mode: settings.fetch(:mode))
        results << { path: path, label: label, source: source, formatted: formatted }
      rescue Ibex::Error, SystemCallError => e
        @stderr.puts(formatting_label(e.message))
        failed = true
      end
      [results, failed]
    end

    # @rbs (Array[formatting_result] results) -> Integer
    def check_formatting_results(results)
      changed = results.reject { |result| result.fetch(:source) == result.fetch(:formatted) }
      changed.each { |result| @stderr.puts("#{result.fetch(:label)}: needs formatting") }
      changed.empty? ? 0 : 1
    end

    # @rbs (Array[formatting_result] results) -> Integer
    def write_formatting_results(results)
      targets = formatting_targets(results)
      validate_unique_formatting_targets!(targets)
      targets = targets.select { |target| target.fetch(:changed) }
      return 0 if targets.empty?

      transactionally_write_formatted(targets)
      0
    end

    # @rbs (Array[formatting_result] results) -> Array[formatting_target]
    def formatting_targets(results)
      results.map do |result|
        target = File.realpath(result.fetch(:path))
        {
          path: result.fetch(:path), label: result.fetch(:label), target: target,
          formatted: result.fetch(:formatted), mode: File.stat(target).mode & 0o7777,
          directory: File.dirname(target), basename: File.basename(target),
          changed: result.fetch(:source) != result.fetch(:formatted), installed: false
        }
      end
    rescue SystemCallError => e
      raise Ibex::Error, formatting_label(e.message)
    end

    # @rbs (Array[formatting_target] targets) -> void
    def validate_unique_formatting_targets!(targets)
      collision = duplicate_formatting_target_pair(targets)
      return unless collision

      labels = collision.map { |target| target.fetch(:label) }
      raise Ibex::Error, "(cli):1:1: fmt inputs resolve to the same target: #{labels.join(', ')}"
    end

    # @rbs (Array[formatting_target] targets) -> [formatting_target, formatting_target]?
    def duplicate_formatting_target_pair(targets)
      targets.each_with_index do |left, index|
        targets.drop(index + 1).each do |right|
          same_path = left.fetch(:target) == right.fetch(:target)
          return [left, right] if same_path || File.identical?(left.fetch(:target), right.fetch(:target))
        end
      end
      nil
    end

    # @rbs (Array[formatting_target] targets) -> void
    def transactionally_write_formatted(targets)
      begin
        stage_formatting_targets(targets)
        backup_formatting_targets(targets)
        sync_formatting_directories!(targets)
        install_formatting_targets(targets)
        sync_formatting_directories!(targets)
      rescue StandardError => e
        rollback_errors = rollback_formatting_targets(targets)
        cleanup = cleanup_formatting_artifacts(targets, preserve_installed_backups: true)
        sync_errors = sync_formatting_directories_best_effort(targets)
        raise formatting_transaction_error(e, rollback_errors, cleanup, sync_errors)
      end

      cleanup = cleanup_formatting_artifacts(targets, preserve_installed_backups: false)
      sync_errors = sync_formatting_directories_best_effort(targets)
      report_formatting_cleanup_warning(cleanup, sync_errors)
    end

    # @rbs (Array[formatting_target] targets) -> void
    def stage_formatting_targets(targets)
      targets.each do |target|
        temporary = Tempfile.create(
          [".ibex-fmt-", ".stage"], target.fetch(:directory)
        )
        target[:stage] = temporary.path.dup
        temporary.binmode
        temporary.write(target.fetch(:formatted))
        temporary.flush
        temporary.fsync
        temporary.chmod(target.fetch(:mode))
        temporary.fsync
        temporary.close
      rescue StandardError
        begin
          temporary&.close
        rescue StandardError
          nil
        end
        raise
      end
    end

    # @rbs (Array[formatting_target] targets) -> void
    def backup_formatting_targets(targets)
      targets.each do |target|
        backup = "#{target.fetch(:stage)}.backup"
        target[:backup] = backup
        File.link(target.fetch(:target), backup)
      end
    end

    # @rbs (Array[formatting_target] targets) -> void
    def install_formatting_targets(targets)
      targets.each do |target|
        File.rename(target.fetch(:stage), target.fetch(:target))
        target[:installed] = true
      end
    end

    # @rbs (Array[formatting_target] targets) -> Array[String]
    def rollback_formatting_targets(targets)
      errors = [] #: Array[String]
      targets.reverse_each do |target|
        next unless target.fetch(:installed)

        File.rename(target.fetch(:backup), target.fetch(:target))
        target[:installed] = false
      rescue StandardError => e
        errors << "#{target.fetch(:label)}: #{formatting_label(e.message)}"
      end
      errors
    end

    # @rbs (Array[formatting_target] targets, preserve_installed_backups: bool) ->
    #   formatting_cleanup_result
    def cleanup_formatting_artifacts(targets, preserve_installed_backups:)
      errors = [] #: Array[String]
      remaining = [] #: Array[String]
      targets.each do |target|
        artifacts = [target[:stage]] #: Array[String?]
        backup = target[:backup]
        if preserve_installed_backups && target.fetch(:installed) && backup
          remaining << backup
        else
          artifacts << backup
        end
        artifacts.compact.each do |path|
          error = remove_formatting_artifact(path)
          next unless error

          errors << error
          remaining << path
        end
      end
      { errors: errors, remaining: remaining }
    end

    # @rbs (String path) -> String?
    def remove_formatting_artifact(path)
      attempts = 0
      begin
        attempts += 1
        File.unlink(path)
        nil
      rescue Errno::ENOENT
        nil
      rescue StandardError => e
        retry if attempts < 2

        "#{formatting_label(path)}: #{formatting_label(e.message)}"
      end
    end

    # @rbs (StandardError error, Array[String] rollback_errors,
    #   formatting_cleanup_result cleanup, Array[String] sync_errors) -> Ibex::Error
    def formatting_transaction_error(error, rollback_errors, cleanup, sync_errors)
      details = ["fmt write failed: #{formatting_label(error.message)}"] #: Array[String]
      details << "rollback failed: #{rollback_errors.join('; ')}" unless rollback_errors.empty?
      details << "cleanup failed: #{cleanup.fetch(:errors).join('; ')}" unless cleanup.fetch(:errors).empty?
      unless cleanup.fetch(:remaining).empty?
        paths = cleanup.fetch(:remaining).map { |path| formatting_label(path) }
        details << "preserved artifacts: #{paths.join(', ')}"
      end
      details << "rollback directory sync failed: #{sync_errors.join('; ')}" unless sync_errors.empty?
      Ibex::Error.new(details.join("; "))
    end

    # @rbs (formatting_cleanup_result cleanup, Array[String] sync_errors) -> void
    def report_formatting_cleanup_warning(cleanup, sync_errors)
      details = cleanup.fetch(:errors).dup
      details.concat(sync_errors)
      unless cleanup.fetch(:remaining).empty?
        paths = cleanup.fetch(:remaining).map { |path| formatting_label(path) }
        details << "remaining artifacts: #{paths.join(', ')}"
      end
      return if details.empty?

      @stderr.puts("fmt cleanup warning (formatted targets committed): #{details.join('; ')}")
    end

    # @rbs (Array[formatting_target] targets) -> void
    def sync_formatting_directories!(targets)
      errors = sync_formatting_directories(targets)
      return if errors.empty?

      raise Ibex::Error, "directory sync failed: #{errors.join('; ')}"
    end

    # @rbs (Array[formatting_target] targets) -> Array[String]
    def sync_formatting_directories_best_effort(targets)
      sync_formatting_directories(targets)
    end

    # @rbs (Array[formatting_target] targets) -> Array[String]
    def sync_formatting_directories(targets)
      errors = [] #: Array[String]
      targets.map { |target| target.fetch(:directory) }.uniq.each do |directory|
        sync_formatting_directory(directory)
      rescue SystemCallError, IOError => e
        errors << "#{formatting_label(directory)}: #{formatting_label(e.message)}"
      end
      errors
    end

    # @rbs (String directory) -> void
    def sync_formatting_directory(directory)
      File.open(directory, File::RDONLY, &:fsync)
    rescue Errno::EINVAL, Errno::ENOTSUP, Errno::EBADF
      nil
    end

    # @rbs (String value) -> String
    def formatting_label(value)
      escaped = String.new(encoding: Encoding::BINARY)
      value.b.each_byte do |byte|
        escaped << (control_byte?(byte) ? format("\\x%02X", byte) : byte)
      end
      escaped.force_encoding(value.encoding)
    end

    # @rbs (String value) -> bool
    def formatting_control_bytes?(value)
      value.b.each_byte.any? { |byte| control_byte?(byte) }
    end

    # @rbs (Integer byte) -> bool
    def control_byte?(byte)
      byte < 0x20 || byte == 0x7f
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
