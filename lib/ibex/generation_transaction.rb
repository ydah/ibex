# frozen_string_literal: true
# rbs_inline: enabled

require "digest"
require "tempfile"
require_relative "error"
require_relative "generation_transaction_recovery"
require_relative "generation_transaction_validation"

module Ibex
  # Publishes a rendered ArtifactSet with rollback and a manifest-last marker.
  class GenerationTransaction
    include GenerationTransactionRecovery
    include GenerationTransactionValidation

    class SourceChanged < Ibex::Error; end

    class Error < Ibex::Error
      attr_reader :rollback_failed #: bool
      attr_reader :recovery_artifacts #: Array[String]

      # @rbs (String message, ?rollback_failed: bool, ?recovery_artifacts: Array[String]) -> void
      def initialize(message, rollback_failed: false, recovery_artifacts: [])
        super(message)
        @rollback_failed = rollback_failed
        @recovery_artifacts = recovery_artifacts.freeze
      end
    end

    # rubocop:disable Layout/LineLength
    # @rbs (ArtifactSet artifacts, ?warning: ^(String) -> void, ?stability_check: ^() -> bool, ?source_records: Array[GenerationInput], ?lock_sleeper: ^(Float) -> void) -> void
    def initialize(artifacts, warning: ->(_message) {}, stability_check: -> { true }, source_records: [],
                   lock_sleeper: ->(seconds) { sleep(seconds) })
      @artifacts = artifacts
      @warning = warning
      @stability_check = stability_check
      @source_records = source_records
      @lock_sleeper = lock_sleeper
      @locks = [] #: Array[File]
      @locked_paths = [] #: Array[String]
      @records = [] #: Array[Hash[Symbol, untyped]]
      @committed = false
    end
    # rubocop:enable Layout/LineLength

    # @rbs () -> void
    def commit
      @committed = false
      prepare_records
      validate_source_boundaries!
      acquire_locks
      prepare_records
      validate_source_boundaries!
      validate_locked_targets!
      ensure_sources_stable!("before staging outputs")
      stage_records
      ensure_sources_stable!("while staging outputs")
      backup_records
      sync_directories!
      install_group(:non_marker)
      sync_directories!
      ensure_sources_stable!("before parser publication")
      install_group(:parser)
      sync_directories!
      ensure_sources_stable!("after parser publication")
      install_group(:manifest)
      sync_directories!
      ensure_sources_stable!("after manifest publication")
      @committed = true
      cleanup_success
    rescue StandardError, SignalException => e
      @committed ? report_post_commit_failure(e) : handle_failure(e)
    ensure
      release_locks
    end

    private

    # @rbs () -> void
    def prepare_records
      @records = @artifacts.map do |artifact|
        target = resolved_target(artifact.path)
        {
          artifact: artifact, target: target, directory: File.dirname(target),
          stage: nil, backup: nil, backed_up: false, installed: false,
          existed: File.exist?(target), mode: target_mode(artifact, target)
        }
      end
      grouped = @records.group_by do |record|
        portable_target_key(record.fetch(:target))
      end
      collision = grouped.find { |_key, records| records.length > 1 }
      return unless collision

      kinds = collision.fetch(1).map { |record| record.fetch(:artifact).kind }.join(", ")
      targets = collision.fetch(1).map { |record| record.fetch(:target) }.join(", ")
      raise Error, "(generation):1:1: artifact targets collide: #{targets} (#{kinds})"
    end

    # @rbs (Artifact artifact, String target) -> Integer
    def target_mode(artifact, target)
      return artifact.mode if artifact.mode
      return File.stat(target).mode & 0o7777 if File.exist?(target)

      mask = File.umask
      File.umask(mask)
      0o666 & ~mask
    end

    # @rbs () -> void
    def acquire_locks
      lock_paths = @records.map { |record| lock_path(record.fetch(:target)) }.uniq.sort
      validate_lock_boundaries!(lock_paths)
      @locked_paths = lock_paths
      @locks = [] #: Array[File]
      lock_paths.each do |path|
        flags = File::RDWR | File::CREAT
        flags |= File.const_get(:NOFOLLOW) if File.const_defined?(:NOFOLLOW)
        lock = File.new(path, flags, 0o600)
        @locks << lock
        validate_lock_identity!(path, lock)
        acquire_lock(lock, path)
        validate_lock_identity!(path, lock)
      end
    end

    # @rbs (File lock, String path) -> void
    def acquire_lock(lock, path)
      until lock.flock(File::LOCK_EX | File::LOCK_NB)
        unless @stability_check.call
          raise SourceChanged, "(generation):1:1: generation cancelled while waiting for lock: #{path}"
        end

        @lock_sleeper.call(0.05)
      end
    end

    # @rbs (String target) -> String
    def lock_path(target)
      digest = Digest::SHA256.hexdigest(target).slice(0, 16)
      File.join(File.dirname(target), ".ibex-generation-#{digest}.lock")
    end

    # @rbs () -> void
    def stage_records
      @records.each do |record|
        temporary = Tempfile.create([".ibex-generation-", ".stage"], record.fetch(:directory))
        begin
          record[:stage] = temporary.path.dup
          temporary.binmode
          temporary.write(record.fetch(:artifact).content)
          temporary.flush
          temporary.chmod(record.fetch(:mode))
          temporary.fsync
        ensure
          temporary.close
        end
      end
    end

    # @rbs () -> void
    def backup_records
      @records.each do |record|
        target = record.fetch(:target)
        next unless File.exist?(target)

        validate_existing_target!(target)
        backup = vacant_temporary_path(record.fetch(:directory), ".backup")
        File.link(target, backup)
        record[:backup] = backup
        record[:backed_up] = true
      end
    end

    # @rbs (String directory, String suffix) -> String
    def vacant_temporary_path(directory, suffix)
      temporary = Tempfile.new([".ibex-generation-", suffix], directory)
      path = temporary.path&.dup
      temporary.close!
      raise Error, "(generation):1:1: temporary path is unavailable in #{directory}" unless path

      path
    end

    # @rbs (Symbol group) -> void
    def install_group(group)
      selected = @records.select { |record| publication_group(record.fetch(:artifact)) == group }
      selected.sort_by { |record| record.fetch(:target) }.each do |record|
        File.rename(record.fetch(:stage), record.fetch(:target))
        record[:stage] = nil
        record[:installed] = true
      end
    end

    # @rbs (Artifact artifact) -> Symbol
    def publication_group(artifact)
      return :manifest if artifact.kind == :manifest
      return :parser if artifact.kind == :parser

      :non_marker
    end

    # @rbs () -> void
    def sync_directories!
      @records.map { |record| record.fetch(:directory) }.uniq.sort.each do |directory|
        File.open(directory, File::RDONLY, &:fsync)
      end
    end

    # @rbs () -> void
    def cleanup_success
      failures = cleanup_artifacts(preserve_backups: false)
      sync_failures = sync_directories_best_effort
      messages = failures + sync_failures
      warn_best_effort("generation cleanup incomplete: #{messages.join('; ')}") unless messages.empty?
    end

    # @rbs (Exception error) -> void
    def report_post_commit_failure(error)
      warn_best_effort("generation committed but cleanup failed: #{error.message}")
    end

    # @rbs (String message) -> void
    def warn_best_effort(message)
      @warning.call(message)
    rescue StandardError
      nil
    end

    # @rbs () -> void
    def release_locks
      @locks.reverse_each do |lock|
        lock.flock(File::LOCK_UN)
        lock.close
      rescue StandardError
        nil
      end
      @locks = [] #: Array[File]
      @locked_paths = [] #: Array[String]
    end
  end
end
