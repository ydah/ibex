# frozen_string_literal: true

require "digest"
require "json"
require "time"

module BenchmarkSupport
  # Builds a diagnostic profile artifact that is deliberately ineligible as release evidence.
  module PublicProfileReport
    WARNING = "Diagnostic profiles include profiler overhead and are not formal performance evidence."

    module_function

    def build(options:, manifest:, checkouts:, profiles:, environment:, formal_commands:)
      {
        artifact: "ibex_public_performance_profile",
        schema_version: 1,
        evidence_kind: "diagnostic_profile",
        formal_evidence: false,
        warning: WARNING,
        recorded_at: Time.now.utc.iso8601,
        environment: environment,
        profiler: profiler_metadata(options),
        configuration: configuration(options),
        manifest: { path: "benchmark/public_workloads.json", sha256: manifest.digest },
        projects: options.fetch(:projects).map do |identifier|
          project(
            identifier, manifest.fetch(identifier), checkouts.fetch(identifier),
            profiles.fetch(identifier), formal_commands.fetch(identifier), options.fetch(:runs)
          )
        end
      }
    end

    def profiler_metadata(options)
      {
        name: "stackprof",
        mode: "wall",
        interval_usec: options.fetch(:interval_usec),
        top_frames: options.fetch(:top_frames),
        raw_profiles: true,
        timing_comparable: false
      }
    end

    def configuration(options)
      {
        runs: options.fetch(:runs),
        warmup_workloads: options.fetch(:warmup),
        profiled_runtime_workloads: options.fetch(:iterations),
        scenarios: %w[cold_generation warm_runtime_reuse warm_runtime_new_instance],
        fresh_process_per_profile: true,
        allow_dirty: options.fetch(:allow_dirty)
      }
    end

    def project(identifier, workload, checkout, profiles, formal_commands, expected_runs)
      validate_profiles!(identifier, profiles, expected_runs)
      {
        id: identifier,
        repository: checkout.except(:root).merge(
          url: workload.fetch("repository_url"),
          expected_revision: workload.fetch("revision"),
          grammar_path: workload.fetch("grammar_path"),
          dependency_definition_path: workload.fetch("dependency_definition_path")
        ),
        workload: {
          id: workload.fetch("workload_id"),
          driver: workload.fetch("driver"),
          input_count: workload.fetch("inputs").length,
          inputs_sha256: Digest::SHA256.hexdigest(JSON.generate(workload.fetch("inputs")))
        },
        formal_commands: formal_commands,
        profiles: profiles
      }
    end

    def validate_profiles!(identifier, profiles, expected_runs)
      grouped = profiles.group_by { |profile| profile.fetch("scenario") }
      expected_scenarios = %w[cold_generation warm_runtime_reuse warm_runtime_new_instance]
      unless grouped.keys.sort == expected_scenarios.sort
        raise "#{identifier} profile scenarios do not match the diagnostic protocol"
      end

      grouped.each do |scenario, entries|
        runs = entries.map { |profile| profile.fetch("run") }.sort
        next if runs == (1..expected_runs).to_a

        raise "#{identifier}/#{scenario} profile runs do not match the diagnostic protocol"
      end
    end
    private_class_method :validate_profiles!
  end
end
