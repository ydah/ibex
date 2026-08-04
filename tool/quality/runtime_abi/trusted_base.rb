# frozen_string_literal: true

require "open3"
require "pathname"
require_relative "document"

module Ibex
  module Quality
    # Loads the ABI path policy from the pull request's trusted base revision.
    class RuntimeABITrustedBase
      include RuntimeABIDocument

      CONTRACT_PATH = "docs/runtime-abi-evolution.md"
      SHA = /\A[0-9a-f]{40,64}\z/
      BOOTSTRAP_RUNTIME_PATHS = %w[
        .github/workflows/**/* .github/pull_request_template.md Rakefile
        docs/runtime-abi-evolution.md docs/test-interactions.md
        tool/quality/runtime_abi.rb tool/quality/runtime_abi/**/*
        test/quality/runtime_abi*_test.rb test/fixtures/runtime_abi/**/*
        lib/ibex/runtime.rb lib/ibex/runtime/**/*
        sig/ibex/runtime.rbs sig/ibex/runtime/**/*
      ].freeze

      def initialize(root:, head_contract:)
        @root = File.expand_path(root)
        @head_paths = validate_patterns(head_contract.fetch("runtime_paths"), "head runtime_paths")
      end

      def union(event)
        base, head = pull_request_shas!(event)
        verify_commit!(base, "base")
        verify_commit!(head, "head")
        (@head_paths + base_paths(base, head)).uniq.freeze
      end

      def pull_request_shas!(event)
        base = event.dig("pull_request", "base", "sha")
        head = event.dig("pull_request", "head", "sha")
        unless base.is_a?(String) && head.is_a?(String) && base.match?(SHA) && head.match?(SHA)
          raise "pull_request event must provide hexadecimal base and head SHAs"
        end

        [base, head]
      end

      private

      def base_paths(base, head)
        source, stderr, status = git("show", "#{base}:#{CONTRACT_PATH}")
        return parse_base_paths(source, base) if status.success?
        return BOOTSTRAP_RUNTIME_PATHS if bootstrap_introduction?(base, head)

        raise "trusted base runtime ABI contract is missing: #{stderr.strip}"
      end

      def parse_base_paths(source, base)
        contract = load_contract_source(source, "runtime-abi", "#{base}:#{CONTRACT_PATH}")
        validate_patterns(contract.fetch("runtime_paths"), "trusted base runtime_paths")
      rescue KeyError => e
        raise "trusted base runtime ABI contract is missing runtime_paths: #{e.message}"
      end

      def bootstrap_introduction?(base, head)
        output, stderr, status = git(
          "diff", "--name-only", "-z", "--no-renames", "--diff-filter=A", "#{base}...#{head}", "--", CONTRACT_PATH
        )
        raise "cannot verify runtime ABI bootstrap: #{stderr.strip}" unless status.success?

        nul_paths(output) == [CONTRACT_PATH]
      end

      def verify_commit!(sha, label)
        _output, stderr, status = git("cat-file", "-e", "#{sha}^{commit}")
        return if status.success?

        raise "pull_request #{label} commit is unavailable: #{stderr.strip}"
      end

      def validate_patterns(patterns, label)
        unless patterns.is_a?(Array) && !patterns.empty? && patterns.all? { |pattern| valid_pattern?(pattern) }
          raise "#{label} must be normalized repository-relative glob strings"
        end
        raise "#{label} must be unique" unless patterns.uniq.length == patterns.length

        patterns
      end

      def valid_pattern?(pattern)
        pattern.is_a?(String) && !pattern.empty? && !pattern.include?("\0") && !pattern.start_with?("/") &&
          pattern.split("/", -1).none? { |part| part.empty? || %w[. ..].include?(part) } &&
          Pathname.new(pattern).cleanpath.to_s == pattern
      end

      def nul_paths(output)
        bytes = output.b
        return [] if bytes.empty?
        raise "git path output is not NUL terminated" unless bytes.end_with?("\0")

        bytes.byteslice(0, bytes.bytesize - 1).split("\0", -1)
      end

      def git(*arguments)
        Open3.capture3("git", *arguments, chdir: @root)
      end
    end
  end
end
