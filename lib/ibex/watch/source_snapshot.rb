# frozen_string_literal: true
# rbs_inline: enabled

require "digest"

module Ibex
  module Watch
    # Stable metadata and content fingerprints for watched source paths.
    class SourceSnapshot
      # @rbs!
      #   type fingerprint_value = Symbol | String | Integer | nil | Hash[Symbol, fingerprint_value]
      #   type fingerprint = Hash[Symbol, fingerprint_value]

      attr_reader :paths #: Array[String]

      # @rbs (Array[String] paths) -> void
      def initialize(paths)
        @paths = paths.map { |path| File.expand_path(path) }.uniq.sort.freeze
        @entries = @paths.to_h { |path| [path, fingerprint(path)] }.freeze #: Hash[String, fingerprint]
        freeze
      end

      # @rbs (SourceSnapshot other) -> bool
      def ==(other)
        @entries == other.__send__(:entries)
      end

      # Every path in this snapshot must have had the same value in the older snapshot.
      # @rbs (SourceSnapshot older) -> bool
      def unchanged_since?(older)
        @paths.all? do |path|
          older.__send__(:entry, path) == @entries.fetch(path)
        end
      end

      protected

      attr_reader :entries #: Hash[String, fingerprint]

      # @rbs (String path) -> fingerprint?
      def entry(path)
        @entries[path]
      end

      private

      # @rbs (String path) -> fingerprint
      def fingerprint(path)
        stat = File.lstat(path)
        value = stat_signature(stat)
        if stat.symlink?
          value[:readlink] = File.readlink(path)
          add_resolved_target(value, path)
        else
          value[:resolved_path] = File.realpath(path)
          value[:sha256] = Digest::SHA256.file(path).hexdigest if stat.file?
        end
        value
      rescue SystemCallError => e
        { kind: :error, error: e.class.name, errno: e.respond_to?(:errno) ? e.errno : nil }
      end

      # @rbs (File::Stat stat) -> fingerprint
      def stat_signature(stat)
        {
          kind: file_kind(stat), dev: stat.dev, ino: stat.ino, size: stat.size,
          mtime_ns: nanoseconds(stat.mtime), ctime_ns: nanoseconds(stat.ctime)
        }
      end

      # @rbs (File::Stat stat) -> Symbol
      def file_kind(stat)
        return :file if stat.file?
        return :directory if stat.directory?
        return :symlink if stat.symlink?

        :other
      end

      # @rbs (Time time) -> Integer
      def nanoseconds(time)
        (time.to_i * 1_000_000_000) + time.nsec
      end

      # @rbs (fingerprint value, String path) -> void
      def add_resolved_target(value, path)
        target = File.realpath(path)
        stat = File.stat(target)
        value[:resolved_path] = target
        resolved = stat_signature(stat)
        resolved[:sha256] = Digest::SHA256.file(target).hexdigest if stat.file?
        value[:resolved] = resolved
      rescue SystemCallError => e
        value[:resolved] = { kind: :error, error: e.class.name, errno: e.respond_to?(:errno) ? e.errno : nil }
      end
    end
  end
end
