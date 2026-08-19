# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Failure recovery and best-effort cleanup for GenerationTransaction.
  module GenerationTransactionRecovery
    private

    # @rbs (Exception cause) -> bot
    def handle_failure(cause)
      rollback_failures = rollback
      cleanup_failures = cleanup_artifacts(preserve_backups: !rollback_failures.empty?)
      sync_failures = sync_directories_best_effort
      raise cause if source_change_clean?(cause, rollback_failures, cleanup_failures, sync_failures)

      recovery = recovery_artifacts
      details = failure_details(cause, rollback_failures, cleanup_failures, sync_failures, recovery)
      raise GenerationTransaction::Error.new(
        "(generation):1:1: #{details.join(' | ')}",
        rollback_failed: !rollback_failures.empty?, recovery_artifacts: recovery
      ), cause: cause
    end

    # @rbs (Exception cause, Array[String] rollback, Array[String] cleanup, Array[String] sync) -> bool
    def source_change_clean?(cause, rollback, cleanup, sync)
      cause.is_a?(GenerationTransaction::SourceChanged) && rollback.empty? && cleanup.empty? && sync.empty?
    end

    # rubocop:disable Layout/LineLength
    # @rbs (Exception cause, Array[String] rollback, Array[String] cleanup, Array[String] sync, Array[String] recovery) -> Array[String]
    def failure_details(cause, rollback, cleanup, sync, recovery)
      details = [cause.message]
      details << "rollback failed: #{rollback.join('; ')}" unless rollback.empty?
      details << "cleanup failed: #{cleanup.join('; ')}" unless cleanup.empty?
      details << "directory sync failed: #{sync.join('; ')}" unless sync.empty?
      details << "recovery artifacts: #{recovery.join(', ')}" unless recovery.empty?
      details
    end
    # rubocop:enable Layout/LineLength

    # @rbs () -> Array[String]
    def recovery_artifacts
      @records.filter_map do |record|
        backup = record[:backup]
        backup if backup && File.exist?(backup)
      end
    end

    # @rbs () -> Array[String]
    def rollback
      failures = [] #: Array[String]
      @records.reverse_each do |record|
        rollback_record(record)
      rescue StandardError => e
        failures << "#{record.fetch(:target)}: #{e.message}"
      end
      failures
    end

    # @rbs (Hash[Symbol, Object?] record) -> void
    def rollback_record(record)
      target = record.fetch(:target) #: String
      if record.fetch(:backed_up)
        if record.fetch(:installed)
          File.rename(record.fetch(:backup).to_s, target)
        else
          File.unlink(record.fetch(:backup).to_s)
        end
        record[:backup] = nil
        record[:backed_up] = false
        record[:installed] = false
      elsif record.fetch(:installed)
        File.unlink(target)
        record[:installed] = false
      end
    end

    # @rbs (preserve_backups: bool) -> Array[String]
    def cleanup_artifacts(preserve_backups:)
      failures = [] #: Array[String]
      @records.each do |record|
        paths = [record[:stage]]
        paths << record[:backup] unless preserve_backups
        paths.compact.each { |path| remove_artifact(path, failures) }
      end
      failures
    end

    # @rbs (String path, Array[String] failures) -> void
    def remove_artifact(path, failures)
      File.unlink(path)
    rescue Errno::ENOENT
      nil
    rescue StandardError => e
      failures << "#{path}: #{e.message}"
    end

    # @rbs () -> Array[String]
    def sync_directories_best_effort
      failures = [] #: Array[String]
      @records.map { |record| record.fetch(:directory) }.uniq.sort.each do |directory|
        sync_directory!(directory)
      rescue StandardError => e
        failures << "#{directory}: #{e.message}"
      end
      failures
    end
  end
end
