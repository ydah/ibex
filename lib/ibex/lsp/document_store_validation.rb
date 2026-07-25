# frozen_string_literal: true

module Ibex
  module LSP
    # Validates versions, source bounds, and prospective multi-file workspace edits.
    module DocumentStoreValidation
      # @rbs (Hash[String, String] replacements) -> bool
      def valid_replacements?(replacements)
        # @type self: DocumentStore
        candidate = Frontend::SourceLoader.new
        @snapshots.each_value do |entry|
          candidate.set_overlay(entry.fetch(:path), entry.fetch(:source)) if entry.fetch(:open)
        end
        replacements.each do |path, source|
          candidate.set_overlay(path, source)
          parse_candidate(path, source)
        end
        roots = replacements.keys.flat_map { |path| affected_roots(path) }.uniq
        roots.each { |root| Frontend::Resolver.new(root, mode: :extended, loader: candidate).resolve }
        true
      rescue Ibex::Error, SystemCallError
        false
      end

      private

      # @rbs (Integer version) -> void
      def validate_version(version)
        raise ProtocolError.new("document version must be a non-negative integer", code: -32_602) unless
          version.is_a?(Integer) && !version.negative?
      end

      # @rbs (String source) -> void
      def validate_source(source)
        raise ProtocolError.new("document text must be a string", code: -32_602) unless source.is_a?(String)
        return if source.bytesize <= Limits::MAX_DOCUMENT_BYTES

        raise ProtocolError.new("document exceeds #{Limits::MAX_DOCUMENT_BYTES} bytes", code: -32_602)
      end

      # @rbs (String path, String source) -> void
      def parse_candidate(path, source)
        Frontend::Parser.new(source, file: path, mode: :extended).parse_source_document
      end

      # Resolve disk independently from overlay aliases before removing an open buffer.
      # @rbs (String path, String uri) -> String?
      def disk_path_for_close(path, uri)
        # @type self: DocumentStore
        canonical = loader.disk_path(path)
        return canonical if workspace.root_for(canonical)

        raise ProtocolError.new("document disk target is outside workspace roots: #{uri}", code: -32_602)
      rescue Errno::ENOENT, Errno::ENOTDIR
        nil
      rescue SystemCallError => e
        raise ProtocolError.new("cannot resolve document disk target #{uri.inspect}: #{e.message}", code: -32_602)
      end
    end
  end
end
