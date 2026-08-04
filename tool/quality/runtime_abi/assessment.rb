# frozen_string_literal: true

require "json"
require "open3"
require "yaml"

module Ibex
  module Quality
    # Validates the machine-readable ABI assessment for runtime-facing PRs.
    class RuntimeABIAssessment
      START = "<!-- ibex-runtime-abi-assessment:start -->"
      FINISH = "<!-- ibex-runtime-abi-assessment:end -->"
      SHA = /\A[0-9a-f]{40,64}\z/

      def initialize(root:, contract:, event_path:, event_name:, changed_paths:)
        @root = File.expand_path(root)
        @contract = contract
        @event_path = event_path
        @event_name = event_name
        @changed_paths = changed_paths
      end

      def verify!
        event = load_event
        pull_request_event = @event_name == "pull_request" || (@event_name.nil? && event.key?("pull_request"))
        return unless pull_request_event

        paths = changed_paths(event)
        runtime_paths = paths.select { |path| runtime_facing?(path) }
        return if runtime_paths.empty?

        body = event.dig("pull_request", "body")
        assessment = parse_assessment(body)
        verify_assessment(assessment, runtime_paths)
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

        file = ENV.fetch("IBEX_ABI_CHANGED_PATHS_FILE", nil)
        return validate_paths(File.readlines(file, chomp: true)) if file

        pull_request_paths(event)
      end

      def pull_request_paths(event)
        base = event.dig("pull_request", "base", "sha")
        head = event.dig("pull_request", "head", "sha")
        unless base.is_a?(String) && head.is_a?(String) && base.match?(SHA) && head.match?(SHA)
          raise "pull_request event must provide hexadecimal base and head SHAs"
        end

        stdout, stderr, status = Open3.capture3(
          "git", "diff", "--name-only", "--no-renames", "#{base}...#{head}", chdir: @root
        )
        raise "cannot derive pull-request changed paths: #{stderr.strip}" unless status.success?

        validate_paths(stdout.lines(chomp: true))
      end

      def validate_paths(paths)
        unless paths.is_a?(Array) && paths.all? { |path| valid_relative_path?(path) }
          raise "changed paths must be normalized repository-relative strings"
        end

        paths.uniq.sort
      end

      def valid_relative_path?(path)
        path.is_a?(String) && !path.empty? && !path.start_with?("/", "../") &&
          !path.include?("/../") && !path.include?("\0")
      end

      def runtime_facing?(changed_path)
        @contract.fetch("runtime_paths").any? do |pattern|
          File.fnmatch?(pattern, changed_path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

      def parse_assessment(body)
        raise "runtime-facing changes require a structured ABI assessment" unless body.is_a?(String)

        pattern = /#{Regexp.escape(START)}\s*```yaml\s*\n(.*?)```\s*#{Regexp.escape(FINISH)}/m
        matches = body.scan(pattern)
        raise "runtime-facing changes require exactly one structured ABI assessment" unless matches.length == 1

        value = YAML.safe_load(matches.fetch(0).fetch(0), permitted_classes: [], aliases: false)
        raise "runtime ABI assessment must be a mapping" unless value.is_a?(Hash)

        value
      rescue Psych::Exception => e
        raise "runtime ABI assessment is invalid YAML: #{e.message}"
      end

      def verify_assessment(value, _runtime_paths)
        policy = @contract.fetch("assessment")
        required = policy.fetch("required_fields")
        unless value.keys.sort == required.sort
          raise "runtime ABI assessment fields must be #{required.sort.join(', ')}"
        end

        state = vocabulary!(value, "state", policy.fetch("states"))
        choice = vocabulary!(value, "abi_choice", policy.fetch("abi_choices"))
        regeneration = vocabulary!(value, "regeneration", policy.fetch("regeneration"))
        surfaces = array_vocabulary!(value, "surfaces", policy.fetch("surfaces"))
        evidence = evidence_paths!(value.fetch("evidence"))

        raise "runtime-facing changes cannot use state not_applicable" if state == "not_applicable"
        raise "runtime-facing changes must declare a concrete surface" if surfaces.include?("none")
        raise "runtime-facing changes must declare evidence paths" if evidence.empty?

        verify_choice(state, choice, regeneration)
      end

      def vocabulary!(value, field, allowed)
        actual = value.fetch(field)
        raise "runtime ABI assessment #{field} must be one of #{allowed.join(', ')}" unless allowed.include?(actual)

        actual
      end

      def array_vocabulary!(value, field, allowed)
        actual = value.fetch(field)
        unless actual.is_a?(Array) && !actual.empty? && actual.uniq.length == actual.length && (actual - allowed).empty?
          raise "runtime ABI assessment #{field} must be a non-empty unique subset of #{allowed.join(', ')}"
        end

        actual
      end

      def evidence_paths!(values)
        unless values.is_a?(Array) && values.all? { |path| valid_relative_path?(path) }
          raise "runtime ABI assessment evidence must contain repository-relative paths"
        end

        missing = values.reject { |path| File.file?(File.join(@root, path)) }
        raise "runtime ABI assessment evidence paths are missing: #{missing.join(', ')}" unless missing.empty?

        values
      end

      def verify_choice(state, choice, regeneration)
        if state == "compatible"
          unless %w[current_contract sidecar].include?(choice)
            raise "compatible assessment must choose current_contract or sidecar"
          end

          raise "compatible assessment must decide regeneration" if regeneration == "not_applicable"

          return
        end

        unless %w[new_table_format new_ir_version new_runtime_major].include?(choice)
          raise "breaking assessment must choose a new table, IR, or runtime-major contract"
        end
        if choice == "new_table_format" && regeneration != "required"
          raise "a new parser-table format requires regeneration"
        end
        raise "breaking assessment must decide regeneration" if regeneration == "not_applicable"
      end
    end
  end
end
