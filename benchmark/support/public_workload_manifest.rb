# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"

module BenchmarkSupport
  # Loads fixed public workloads and verifies supplied checkouts before execution.
  class PublicWorkloadManifest
    REQUIRED_KEYS = %w[
      id repository_url revision grammar_path lockfile_path driver workload_id inputs
    ].freeze

    attr_reader :path

    def initialize(path)
      @path = File.expand_path(path)
      @document = JSON.parse(File.read(@path))
      validate_document!
    end

    def digest
      Digest::SHA256.file(path).hexdigest
    end

    def fetch(identifier)
      workload = workloads.find { |entry| entry.fetch("id") == identifier }
      raise ArgumentError, "unknown public workload #{identifier.inspect}" unless workload

      workload
    end

    def ids
      workloads.map { |entry| entry.fetch("id") }
    end

    def verify_checkout(identifier, root, allow_dirty:)
      workload = fetch(identifier)
      checkout = File.realpath(root)
      revision = capture!(checkout, "git", "rev-parse", "HEAD")
      unless revision == workload.fetch("revision")
        raise "#{identifier} must be checked out at #{workload.fetch('revision')}"
      end

      origin = capture!(checkout, "git", "remote", "get-url", "origin")
      unless normalize_repository(origin) == normalize_repository(workload.fetch("repository_url"))
        raise "#{identifier} origin does not match the manifest"
      end

      status = capture!(checkout, "git", "status", "--porcelain=v1", "--untracked-files=normal").lines(chomp: true)
      if status.any? && !allow_dirty
        raise "#{identifier} checkout is dirty; pass --allow-dirty-checkouts only for diagnostics"
      end

      checkout_metadata(workload, checkout, origin, status)
    rescue Errno::ENOENT => e
      raise ArgumentError, "invalid checkout for #{identifier}: #{e.message}"
    end

    private

    def workloads
      @document.fetch("workloads")
    end

    def validate_document!
      raise "public workload manifest must use schema version 1" unless @document["schema_version"] == 1
      raise "public workload manifest must contain workloads" unless workloads.is_a?(Array) && !workloads.empty?
      raise "public workload identifiers must be unique" unless ids.uniq.length == ids.length

      workloads.each { |workload| validate_workload!(workload) }
    end

    def validate_workload!(workload)
      raise "public workload entry must be an object" unless workload.is_a?(Hash)
      raise "public workload keys changed" unless workload.keys.sort == REQUIRED_KEYS.sort
      raise "public workload revision must be full SHA-1" unless workload.fetch("revision").match?(/\A[0-9a-f]{40}\z/)

      %w[grammar_path lockfile_path].each { |key| validate_relative_path!(workload.fetch(key)) }
      inputs = workload.fetch("inputs")
      valid_inputs = inputs.is_a?(Array) && inputs.all? { |input| input.is_a?(String) && !input.empty? }
      raise "public workload inputs must be non-empty strings" unless valid_inputs
    end

    def validate_relative_path!(path)
      clean = Pathname.new(path).cleanpath.to_s
      invalid = Pathname.new(path).absolute? || clean != path || clean.start_with?("../")
      raise "public workload paths must be relative and normalized" if invalid
    end

    def checkout_metadata(workload, checkout, origin, status)
      grammar = File.join(checkout, workload.fetch("grammar_path"))
      lockfile = File.join(checkout, workload.fetch("lockfile_path"))
      {
        root: checkout,
        origin: origin,
        revision: workload.fetch("revision"),
        dirty: status.any?,
        tracked_dirty: status.any? { |line| !line.start_with?("??") },
        untracked_dirty: status.any? { |line| line.start_with?("??") },
        status_sha256: Digest::SHA256.hexdigest(status.join("\n")),
        grammar_sha256: Digest::SHA256.file(grammar).hexdigest,
        lockfile_sha256: Digest::SHA256.file(lockfile).hexdigest,
        library_tree_oid: capture!(checkout, "git", "rev-parse", "HEAD:lib")
      }
    end

    def normalize_repository(value)
      value.sub(/\Agit@github\.com:/, "https://github.com/").sub(/\.git\z/, "").downcase
    end

    def capture!(directory, *command)
      stdout, stderr, status = Open3.capture3(*command, chdir: directory)
      raise "checkout metadata command failed: #{stderr}#{stdout}" unless status.success?

      stdout.strip
    end
  end
end
