# frozen_string_literal: true

require "date"
require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"
require_relative "identity"

module Ibex
  module Quality
    class ErrorUXReviewPublication
      LOGIN = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?\z/
      BLOB_URL = %r{\Ahttps://github\.com/(?<owner>[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?)/
                    (?<repository>[A-Za-z0-9_.-]+)/blob/(?<revision>[0-9a-f]{40})/(?<path>[^?#%]+)\z}x
      RECORD_KEYS = %w[record_path sha256 permalink source publisher_github_login import_vetting].freeze
      SOURCE_KEYS = %w[owner repository revision path raw_url].freeze
      VETTING_KEYS = %w[
        vetted_by_github_login vetted_on source_bytes_verified publisher_account_metadata_reviewed
      ].freeze

      def initialize(root:, kit:)
        @root = root
        @kit = kit
      end

      def verify!(registration, record)
        ErrorUXReviewIdentity.exact_keys!(registration, RECORD_KEYS, "review publication")
        source = registration.fetch("source")
        vetting = registration.fetch("import_vetting")
        ErrorUXReviewIdentity.exact_keys!(source, SOURCE_KEYS, "review publication source")
        ErrorUXReviewIdentity.exact_keys!(vetting, VETTING_KEYS, "review import vetting")

        verify_record_path!(registration.fetch("record_path"))
        verify_source!(registration.fetch("permalink"), source)
        verify_publisher!(registration.fetch("publisher_github_login"), source.fetch("owner"), record)
        verify_vetting!(vetting)
        registration
      end

      private

      def verify_record_path!(relative)
        expected_prefix = "#{@kit.fetch('records_directory')}/"
        path = ErrorUXReviewIdentity.repository_path(@root, relative, "review record")
        raise "review record must be a JSON file below #{expected_prefix}" unless
          relative.start_with?(expected_prefix) && relative.end_with?(".json") && File.file?(path)
      end

      def verify_source!(permalink, source)
        match = permalink.match(BLOB_URL)
        raise "review permalink must be one canonical full-SHA GitHub blob URL" unless match

        identity = match.named_captures
        expected = SOURCE_KEYS.first(4).map { |key| identity.fetch(key) }
        raise "review permalink source identity mismatch" unless source.values_at(*SOURCE_KEYS.first(4)) == expected

        repository = source.fetch("repository")
        raise "review repository identity is noncanonical" if %w[. ..].include?(repository)

        verify_path!(source.fetch("path"))
        canonical = "https://github.com/#{source.fetch('owner')}/#{source.fetch('repository')}/blob/" \
                    "#{source.fetch('revision')}/#{source.fetch('path')}"
        raise "review permalink is not canonical" unless permalink == canonical

        raw = "https://raw.githubusercontent.com/#{source.fetch('owner')}/#{source.fetch('repository')}/" \
              "#{source.fetch('revision')}/#{source.fetch('path')}"
        raise "review raw source identity mismatch" unless source.fetch("raw_url") == raw
      end

      def verify_path!(path)
        segments = path.split("/", -1)
        invalid = segments.empty? || segments.any? { |segment| segment.empty? || %w[. ..].include?(segment) }
        invalid ||= path.include?("\\") || path.match?(/[\x00-\x1f\x7f]/)
        invalid ||= !path.match?(%r{\A[A-Za-z0-9._~/-]+\z})
        raise "review blob path is empty, traversing, encoded, or noncanonical" if invalid
      end

      def verify_publisher!(publisher, source_owner, record)
        raise "publisher login is not a canonical GitHub login" unless publisher.match?(LOGIN)

        reviewer = record.dig("reviewer", "github_login")
        unless publisher.casecmp?(reviewer) && publisher.casecmp?(source_owner)
          raise "review source owner, publisher, and independent reviewer logins must agree"
        end
        return unless @kit.fetch("maintainer_github_logins").any? { |login| login.casecmp?(publisher) }

        raise "publication publisher is a rostered project maintainer"
      end

      def verify_vetting!(vetting)
        unless vetting.values_at("source_bytes_verified", "publisher_account_metadata_reviewed") == [true, true]
          raise "import vetting must attest source-byte and publisher-account-metadata checks"
        end

        importer = vetting.fetch("vetted_by_github_login")
        unless @kit.fetch("maintainer_github_logins").any? { |login| login.casecmp?(importer) }
          raise "import vetting must name a rostered maintainer login"
        end

        date = Date.iso8601(vetting.fetch("vetted_on"))
        raise "import vetting date cannot be in the future" if date > Date.today
      rescue Date::Error
        raise "import vetting date must be an ISO 8601 calendar date"
      end
    end

    class ErrorUXReviewStrictFetcher
      API = "https://api.github.com"

      def initialize(token: ENV.fetch("GITHUB_TOKEN", nil), transport: nil)
        @token = token
        @transport = transport
      end

      def blob_bytes(source)
        response = request(URI(source.fetch("raw_url")), accept: "application/octet-stream")
        response.body.b
      end

      def commit_author(source)
        uri = URI("#{API}/repos/#{source.fetch('owner')}/#{source.fetch('repository')}/commits/" \
                  "#{source.fetch('revision')}")
        document = JSON.parse(request(uri, accept: "application/vnd.github+json").body)
        raise "GitHub commit API returned the wrong revision" unless document.fetch("sha") == source.fetch("revision")

        login = document.dig("author", "login")
        raise "GitHub commit API did not identify a canonical author login" unless login.is_a?(String)

        login
      rescue JSON::ParserError, KeyError => e
        raise "GitHub commit API response is invalid: #{e.message}"
      end

      private

      def request(uri, accept:)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = accept
        request["User-Agent"] = "ibex-error-ux-review-gate"
        request["Authorization"] = "Bearer #{@token}" if @token && !@token.empty?
        response = if @transport
                     @transport.call(uri, request)
                   else
                     Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
                   end
        raise "external review fetch redirected ambiguously" if response["location"]
        raise "external review fetch failed with HTTP #{response.code}" unless response.code == "200"

        response
      rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
        raise "external review fetch failed closed: #{e.class}: #{e.message}"
      end
    end

    class ErrorUXReviewRemoteVerifier
      def initialize(fetcher:)
        @fetcher = fetcher
      end

      def verify!(registration, local_bytes, record)
        source = registration.fetch("source")
        remote_bytes = @fetcher.blob_bytes(source)
        raise "external review blob bytes differ from the imported payload" unless remote_bytes == local_bytes
        raise "external review blob digest differs from status" unless
          ErrorUXReviewIdentity.digest(remote_bytes) == registration.fetch("sha256")

        author = @fetcher.commit_author(source)
        reviewer = record.dig("reviewer", "github_login")
        publisher = registration.fetch("publisher_github_login")
        owner = source.fetch("owner")
        unless author.casecmp?(reviewer) && author.casecmp?(publisher) && author.casecmp?(owner)
          raise "GitHub publication author, source owner, reviewer, and publisher logins do not agree"
        end

        true
      rescue StandardError => e
        raise "R001 external publication verification failed closed: #{e.message}"
      end
    end
  end
end
