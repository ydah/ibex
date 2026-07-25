# frozen_string_literal: true

module Ibex
  module Frontend
    # Resolves canonical grammar paths and reads either open-buffer overlays or disk.
    class SourceLoader
      # @rbs @overlays: Hash[String, String]
      # @rbs @aliases: Hash[String, String]

      # @rbs (?overlays: Hash[String, String]) -> void
      def initialize(overlays: {})
        @overlays = {} #: Hash[String, String]
        @aliases = {} #: Hash[String, String]
        overlays.each { |path, source| set_overlay(path, source) }
      end

      # Canonicalize an existing file, or a missing path explicitly allowed by an open overlay.
      # @rbs (String path, ?base: String, ?allow_missing: bool) -> String
      def canonical_path(path, base: Dir.pwd, allow_missing: false)
        expanded = File.expand_path(path, base)
        aliased = @aliases[expanded]
        return aliased if aliased

        begin
          File.realpath(expanded)
        rescue Errno::ENOENT
          canonical = canonical_missing_path(expanded)
          return canonical if allow_missing || @overlays.key?(canonical)

          raise
        end
      end

      # @rbs (String path) -> String
      def read(path)
        canonical = canonical_path(path, allow_missing: true)
        overlay = @overlays[canonical]
        return overlay if overlay

        File.binread(canonical)
      end

      # @rbs (String path) -> bool
      def file?(path)
        canonical = canonical_path(path, allow_missing: true)
        @overlays.key?(canonical) || File.file?(canonical)
      rescue SystemCallError
        false
      end

      # @rbs (String path) -> bool
      def overlay?(path)
        canonical = canonical_path(path, allow_missing: true)
        @overlays.key?(canonical)
      rescue SystemCallError
        false
      end

      # Install or replace an editor buffer without writing it to disk.
      # @rbs (String path, String source) -> String
      def set_overlay(path, source)
        expanded = File.expand_path(path)
        canonical = canonical_path(expanded, allow_missing: true)
        raise ArgumentError, "overlay path must not be a directory" if File.directory?(canonical)

        @aliases[expanded] = canonical
        @overlays[canonical] = source.dup.freeze
        canonical
      end

      # Remove an editor buffer and return its canonical path.
      # @rbs (String path) -> String
      def delete_overlay(path)
        expanded = File.expand_path(path)
        canonical = @aliases.delete(expanded) || canonical_path(expanded, allow_missing: true)
        @aliases.delete_if { |_alias_path, target| target == canonical }
        @overlays.delete(canonical)
        canonical
      end

      # Read disk while deliberately bypassing an open overlay.
      # @rbs (String path) -> String
      def disk_source(path)
        File.binread(disk_path(path))
      end

      # @rbs (String path) -> bool
      def disk_file?(path)
        File.file?(disk_path(path))
      rescue SystemCallError
        false
      end

      # Resolve the current disk target without consulting overlay aliases.
      # @rbs (String path) -> String
      def disk_path(path)
        File.realpath(File.expand_path(path))
      end

      private

      # Resolve the nearest existing ancestor so symlink escapes remain visible for new files.
      # @rbs (String expanded) -> String
      def canonical_missing_path(expanded)
        raise Errno::ENOENT, expanded if File.symlink?(expanded)

        cursor = expanded
        suffix = [] #: Array[String]
        loop do
          parent = File.dirname(cursor)
          raise Errno::ENOENT, expanded if parent == cursor

          suffix.unshift(File.basename(cursor))
          cursor = parent
          break if File.exist?(cursor) || File.symlink?(cursor)
        end
        raise Errno::ENOTDIR, cursor unless File.directory?(File.realpath(cursor))

        File.join(File.realpath(cursor), *suffix)
      end
    end
  end
end
