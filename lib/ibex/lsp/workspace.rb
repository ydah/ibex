# frozen_string_literal: true

module Ibex
  module LSP
    # Converts file URIs to canonical paths constrained to initialized workspace roots.
    class Workspace
      attr_reader :roots #: Array[String]

      # @rbs (Array[String] root_uris, Frontend::SourceLoader loader) -> void
      def initialize(root_uris, loader)
        raise ProtocolError.new("initialize requires a workspace root", code: -32_602) if root_uris.empty?

        @loader = loader
        @roots = root_uris.map { |uri| canonical_root(uri) }.uniq.sort.freeze
      end

      # @rbs (String uri, ?allow_missing: bool) -> String
      def path(uri, allow_missing: true)
        parsed = parse_file_uri(uri)
        decoded = decode_path(parsed.path)

        canonical = @loader.canonical_path(decoded, allow_missing: allow_missing)
        return canonical if root_for(canonical)

        raise ProtocolError.new("document is outside initialized workspace roots: #{uri}", code: -32_602)
      rescue URI::InvalidURIError, ArgumentError => e
        raise ProtocolError.new("invalid file URI #{uri.inspect}: #{e.message}", code: -32_602)
      rescue SystemCallError => e
        raise ProtocolError.new("cannot resolve file URI #{uri.inspect}: #{e.message}", code: -32_602)
      end

      # @rbs (String path) -> String
      def uri(path)
        canonical = @loader.canonical_path(path, allow_missing: true)
        parser = begin
          URI::RFC2396_PARSER
        rescue NameError
          URI::DEFAULT_PARSER
        end
        "file://#{parser.escape(canonical)}"
      end

      # @rbs (String path) -> String?
      def root_for(path)
        roots.select { |root| inside?(path, root) }.max_by(&:length)
      end

      private

      # URI is a stdlib boundary whose implementation class varies by scheme.
      # @rbs (String uri) -> untyped
      def parse_file_uri(uri)
        validate_raw_authority!(uri)
        parsed = URI.parse(uri)
        path = parsed.path
        local_host = parsed.host.nil? || parsed.host.empty? || parsed.host.casecmp?("localhost")
        unless parsed.scheme == "file" && local_host &&
               parsed.query.nil? && parsed.fragment.nil? && path&.start_with?("/")
          raise ArgumentError, "only absolute local file URIs are supported"
        end

        parsed
      end

      # Ruby's URI::File may discard userinfo and port, so validate the raw authority first.
      # @rbs (String uri) -> void
      def validate_raw_authority!(uri)
        match = uri.match(%r{\Afile://([^/]*)}i)
        return unless match

        authority = match[1] || ""
        return if authority.empty? || authority.casecmp?("localhost")

        raise ArgumentError, "only an empty authority or localhost is supported"
      end

      # @rbs (String uri) -> String
      def canonical_root(uri)
        parsed = parse_file_uri(uri)
        decoded = decode_path(parsed.path)
        canonical = File.realpath(decoded)
        unless File.directory?(canonical)
          raise ProtocolError.new("workspace root is not a directory: #{uri}", code: -32_602)
        end

        canonical
      rescue URI::InvalidURIError, ArgumentError, SystemCallError => e
        raise ProtocolError.new("invalid workspace root #{uri.inspect}: #{e.message}", code: -32_602)
      end

      # @rbs (String encoded) -> String
      def decode_path(encoded)
        raise ArgumentError, "file URI contains an invalid percent escape" if
          encoded.match?(/%(?![0-9A-Fa-f]{2})/)
        if encoded.match?(/%(?:2f|5c|00)/i)
          raise ArgumentError, "file URI must not percent-encode a path separator or NUL"
        end

        parser = begin
          URI::RFC2396_PARSER
        rescue NameError
          URI::DEFAULT_PARSER
        end
        decoded = parser.unescape(encoded)
        raise ArgumentError, "file URI path must be valid UTF-8" unless decoded.valid_encoding?
        raise ArgumentError, "file URI path must not contain NUL" if decoded.include?("\0")
        raise ArgumentError, "file URI path must not contain parent traversal" if
          decoded.split(%r{[\\/]}).include?("..")

        decoded
      end

      # @rbs (String path, String root) -> bool
      def inside?(path, root)
        cursor = path
        loop do
          return true if cursor == root

          parent = File.dirname(cursor)
          return false if parent == cursor

          cursor = parent
        end
      end
    end
  end
end
