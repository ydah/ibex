# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "assessment_fields"
require_relative "trusted_base"

module Ibex
  module Quality
    # Validates the machine-readable ABI assessment for runtime-facing PRs.
    class RuntimeABIAssessment
      START = "<!-- ibex-runtime-abi-assessment:start -->"
      FINISH = "<!-- ibex-runtime-abi-assessment:end -->"
      def initialize(root:, contract:, test_contract:, event_path:, event_name:, changed_paths:)
        @root = File.expand_path(root)
        @contract = contract
        @test_contract = test_contract
        @event_path = event_path
        @event_name = event_name
        @changed_paths = changed_paths
      end

      def verify!
        event = load_event
        pull_request_event = @event_name == "pull_request" || (@event_name.nil? && event.key?("pull_request"))
        return unless pull_request_event

        trusted_base = RuntimeABITrustedBase.new(root: @root, head_contract: @contract)
        runtime_patterns = trusted_base.union(event)
        paths = changed_paths(event)
        runtime_paths = paths.select { |path| runtime_facing?(path, runtime_patterns) }
        return if runtime_paths.empty?

        body = event.dig("pull_request", "body")
        assessment = parse_assessment(body)
        RuntimeABIAssessmentFields.new(
          root: @root, contract: @contract, test_contract: @test_contract,
          changed_paths: paths, runtime_paths: runtime_paths
        ).verify!(assessment)
      end

      private

      def load_event
        return {} unless @event_path
        raise "GitHub event file is missing: #{@event_path}" unless File.file?(@event_path)

        value = JSON.parse(File.binread(@event_path))
        raise "GitHub event must be a JSON object" unless value.is_a?(Hash)

        value
      rescue JSON::ParserError => e
        raise "GitHub event is invalid JSON: #{e.message}"
      end

      def changed_paths(event)
        return validate_paths(@changed_paths) if @changed_paths

        pull_request_paths(event)
      end

      def pull_request_paths(event)
        base, head = RuntimeABITrustedBase.new(root: @root, head_contract: @contract).pull_request_shas!(event)

        stdout, stderr, status = Open3.capture3(
          "git", "diff", "--name-only", "-z", "--no-renames", "#{base}...#{head}", chdir: @root
        )
        raise "cannot derive pull-request changed paths: #{stderr.strip}" unless status.success?

        validate_paths(nul_paths(stdout))
      end

      def validate_paths(paths)
        raise "changed paths must be normalized repository-relative strings" unless paths.is_a?(Array)

        normalized = paths.map { |path| normalized_relative_path(path) }
        raise "changed paths must be unique" unless normalized.uniq.length == normalized.length

        normalized.sort
      end

      def nul_paths(output)
        bytes = output.b
        return [] if bytes.empty?
        raise "git diff path output is not NUL terminated" unless bytes.end_with?("\0")

        bytes.byteslice(0, bytes.bytesize - 1).split("\0", -1)
      end

      def normalized_relative_path(path)
        raise "changed path must be a String" unless path.is_a?(String)

        value = path.b.dup.force_encoding(Encoding::UTF_8)
        unless value.valid_encoding? && !value.empty? && !value.include?("\0") && !value.start_with?("/") &&
               value.split("/", -1).none? { |part| part.empty? || %w[. ..].include?(part) } &&
               Pathname.new(value).cleanpath.to_s == value
          raise "changed paths must be normalized repository-relative UTF-8 strings"
        end

        value
      end

      def runtime_facing?(changed_path, patterns)
        patterns.any? do |pattern|
          File.fnmatch?(pattern, changed_path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

      def parse_assessment(body)
        raise "runtime-facing changes require a structured ABI assessment" unless body.is_a?(String)
        unless body.scan(START).length == 1 && body.scan(FINISH).length == 1
          raise "runtime-facing changes require exactly one complete structured ABI assessment"
        end

        pattern = /#{Regexp.escape(START)}\s*```yaml\s*\n(.*?)```\s*#{Regexp.escape(FINISH)}/m
        matches = body.scan(pattern)
        raise "runtime-facing changes require exactly one structured ABI assessment" unless matches.length == 1

        value = YAML.safe_load(matches.fetch(0).fetch(0), permitted_classes: [], aliases: false)
        raise "runtime ABI assessment must be a mapping" unless value.is_a?(Hash)

        value
      rescue Psych::Exception => e
        raise "runtime ABI assessment is invalid YAML: #{e.message}"
      end
    end
  end
end
