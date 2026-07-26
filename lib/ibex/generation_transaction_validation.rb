# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Canonical target, source, symlink, and lock identity checks for generation.
  module GenerationTransactionValidation
    # @rbs!
    #   private def lock_path: (String) -> String

    private

    # Follow a final symlink while preserving the symlink path itself during publication.
    # @rbs (String path, ?Hash[String, bool] seen, ?validate_links: bool) -> String
    def resolved_target(path, seen = {}, validate_links: true)
      expanded = File.expand_path(path)
      if File.symlink?(expanded)
        raise Errno::ELOOP, expanded if seen[expanded]

        seen[expanded] = true
        linked = File.expand_path(File.readlink(expanded), File.dirname(expanded))
        return resolved_target(linked, seen, validate_links: validate_links)
      end
      return existing_target(expanded, validate_links) if File.exist?(expanded)

      parent = File.realpath(File.dirname(expanded))
      raise Errno::ENOTDIR, parent unless File.directory?(parent)

      File.join(parent, File.basename(expanded))
    end

    # @rbs (String expanded, bool validate_links) -> String
    def existing_target(expanded, validate_links)
      target = File.realpath(expanded)
      validate_existing_target!(target) if validate_links
      target
    end

    # @rbs (String target) -> void
    def validate_existing_target!(target)
      stat = File.stat(target)
      unless stat.file?
        raise GenerationTransaction::Error,
              "(generation):1:1: output target is not a regular file: #{target}"
      end
      return unless stat.nlink > 1

      raise GenerationTransaction::Error,
            "(generation):1:1: output target has multiple hard links: #{target}"
    end

    # @rbs () -> void
    def validate_source_boundaries!
      source_paths = @source_records.map(&:path)
      @records.each do |record|
        target = record.fetch(:target)
        collision = source_paths.find { |source| paths_alias?(target, source) }
        next unless collision

        raise GenerationTransaction::Error,
              "(generation):1:1: artifact target aliases generation input: #{target} (#{collision})"
      end
    end

    # @rbs (Array[String] lock_paths) -> void
    def validate_lock_boundaries!(lock_paths)
      protected_paths = protected_generation_paths
      lock_paths.each do |path|
        if File.symlink?(path)
          raise GenerationTransaction::Error,
                "(generation):1:1: generation lock must not be a symlink: #{path}"
        end

        collision = protected_paths.find { |protected| paths_alias?(path, protected) }
        next unless collision

        raise GenerationTransaction::Error,
              "(generation):1:1: generation lock aliases a protected path: #{path} (#{collision})"
      end
    end

    # @rbs (String path, File lock) -> void
    def validate_lock_identity!(path, lock)
      path_stat = File.lstat(path)
      lock_stat = lock.stat
      unless stable_lock_identity?(path_stat, lock_stat)
        raise GenerationTransaction::Error,
              "(generation):1:1: generation lock identity changed while opening: #{path}"
      end
      return unless protected_generation_stats.any? { |stat| same_inode?(stat, lock_stat) }

      raise GenerationTransaction::Error,
            "(generation):1:1: generation lock aliases a protected inode: #{path}"
    end

    # @rbs () -> Array[String]
    def protected_generation_paths
      @source_records.map(&:path) + @records.map { |record| record.fetch(:target) }
    end

    # @rbs () -> Array[File::Stat]
    def protected_generation_stats
      protected_generation_paths.filter_map { |path| File.stat(path) if File.exist?(path) }
    end

    # @rbs (File::Stat path_stat, File::Stat lock_stat) -> bool
    def stable_lock_identity?(path_stat, lock_stat)
      path_stat.file? && path_stat.nlink == 1 && same_inode?(path_stat, lock_stat)
    end

    # @rbs (File::Stat left, File::Stat right) -> bool
    def same_inode?(left, right)
      left.dev == right.dev && left.ino == right.ino
    end

    # @rbs (String left, String right) -> bool
    def paths_alias?(left, right)
      return true if File.expand_path(left) == File.expand_path(right)
      return true if portable_target_key(left) == portable_target_key(right)
      return false unless File.exist?(left) && File.exist?(right)

      File.identical?(left, right)
    rescue SystemCallError
      true
    end

    # Reject target names that collide on common case-insensitive or
    # normalization-insensitive filesystems, even when the current filesystem
    # would permit both names.
    # @rbs (String path) -> [String, String]
    def portable_target_key(path)
      basename = File.basename(path)
      folded = if basename.encoding == Encoding::UTF_8 && basename.valid_encoding?
                 basename.unicode_normalize(:nfc).downcase(:fold).unicode_normalize(:nfc)
               else
                 basename.downcase
               end
      [File.dirname(path), folded]
    end

    # @rbs (String phase) -> void
    def ensure_sources_stable!(phase)
      validate_active_locks!(phase)
      validate_current_targets!(phase)
      return if @stability_check.call

      raise GenerationTransaction::SourceChanged, "(generation):1:1: source changed #{phase}"
    end

    # @rbs (String phase) -> void
    def validate_active_locks!(phase)
      @locked_paths.zip(@locks).each do |path, lock|
        next if stable_lock_identity?(File.lstat(path), lock.stat)

        raise GenerationTransaction::SourceChanged,
              "(generation):1:1: generation lock changed #{phase}: #{path}"
      end
    rescue SystemCallError => e
      raise GenerationTransaction::SourceChanged,
            "(generation):1:1: cannot revalidate generation lock #{phase}: #{e.message}"
    end

    # @rbs (String phase) -> void
    def validate_current_targets!(phase)
      sources = @source_records.map(&:path)
      @records.each do |record|
        validate_current_target!(record, sources, phase)
      end
    rescue SystemCallError => e
      raise GenerationTransaction::SourceChanged,
            "(generation):1:1: cannot revalidate artifact target #{phase}: #{e.message}"
    end

    # @rbs (Hash[Symbol, untyped] record, Array[String] sources, String phase) -> void
    def validate_current_target!(record, sources, phase)
      artifact = record.fetch(:artifact)
      current = resolved_target(artifact.path, validate_links: false)
      unless current == record.fetch(:target)
        raise GenerationTransaction::SourceChanged,
              "(generation):1:1: artifact target changed #{phase}: #{artifact.path}"
      end
      return unless sources.any? { |source| paths_alias?(current, source) }

      raise GenerationTransaction::SourceChanged,
            "(generation):1:1: artifact target aliases an input #{phase}: #{artifact.path}"
    end

    # @rbs () -> void
    def validate_locked_targets!
      current = @records.map { |record| lock_path(record.fetch(:target)) }.uniq.sort
      return if current == @locked_paths

      raise GenerationTransaction::Error,
            "(generation):1:1: output target changed while acquiring generation locks"
    end
  end
end
