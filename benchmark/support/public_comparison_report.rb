# frozen_string_literal: true

require "digest"
require "json"
require_relative "comparison_statistics"

module BenchmarkSupport
  # Assembles public-workload observations under the owned comparison contract.
  # rubocop:disable Metrics/ModuleLength -- one report schema owns these projections.
  module PublicComparisonReport
    module_function

    def build(options, manifest, checkouts, observations, environment:)
      assert_formal_eligibility!(options, checkouts, environment)
      projects = options.fetch(:projects).map do |identifier|
        project_report(
          identifier, options, manifest, checkouts.fetch(identifier), observations.fetch(identifier), environment
        )
      end
      {
        artifact: "ibex_racc_public_performance_comparison",
        schema_version: 1,
        evidence_kind: options.fetch(:smoke) ? "diagnostic_smoke" : "formal",
        recorded_at: Time.now.utc.iso8601,
        third_party_code_warning: PublicPerformanceComparison::THIRD_PARTY_WARNING,
        environment: environment,
        configuration: configuration(options),
        manifest: {
          path: "benchmark/public_workloads.json",
          sha256: manifest.digest
        },
        projects: projects
      }
    end

    def project_report(identifier, options, manifest, checkout, observations, environment)
      assert_observation_counts!(observations, options.fetch(:runs))
      PerformanceComparison.assert_worker_environment!(observations, environment)
      PerformanceComparison.assert_racc_backend!(observations, options.fetch(:expected_racc_backend))
      assert_equivalent!(observations)
      workload = manifest.fetch(identifier)
      {
        id: identifier,
        repository: repository_metadata(workload, checkout),
        workload: workload_metadata(workload),
        commands: command_metadata(options, identifier),
        scenarios: observations.to_h do |scenario, implementations|
          [scenario.to_sym, summarize_scenario(scenario, implementations, options, identifier)]
        end
      }
    end

    def assert_formal_eligibility!(options, checkouts, environment)
      return if options.fetch(:smoke)

      raise "formal reports require Racc's Ruby backend" unless options.fetch(:expected_racc_backend) == "ruby"
      raise "formal reports require at least ten isolated runs" if options.fetch(:runs) < 10
      raise "formal reports cannot allow dirty checkouts" if options.fetch(:allow_dirty)

      root_dirty = %i[git_dirty git_tracked_dirty git_untracked_dirty].any? { |key| environment.fetch(key) }
      raise "formal reports require a clean Ibex repository root" if root_dirty

      dirty_checkouts = checkouts.select do |_identifier, checkout|
        %i[dirty tracked_dirty untracked_dirty].any? { |key| checkout.fetch(key) }
      end
      return if dirty_checkouts.empty?

      raise "formal reports require clean public checkouts: #{dirty_checkouts.keys.join(', ')}"
    end

    def assert_observation_counts!(observations, expected)
      scenarios = PublicComparisonWorker::SCENARIOS
      raise "public comparison scenarios do not match the protocol" unless observations.keys.sort == scenarios.sort

      observations.each do |scenario, implementations|
        unless implementations.keys.sort == PublicComparisonWorker::IMPLEMENTATIONS.sort
          raise "#{scenario} implementations do not match the protocol"
        end

        implementations.each do |implementation, entries|
          next if entries.length == expected

          raise "#{scenario}/#{implementation} has #{entries.length} observations; expected #{expected}"
        end
      end
    end

    def summarize_scenario(scenario, observations, options, identifier)
      summaries = observations.transform_values do |entries|
        scenario == "cold_generation" ? generation_summary(entries) : runtime_summary(entries)
      end
      comparison = if scenario == "cold_generation"
                     generation_comparison(summaries, options, identifier)
                   else
                     runtime_comparison(summaries, options, identifier, scenario)
                   end
      { implementations: summaries.transform_keys(&:to_sym), comparison: comparison }
    end

    def generation_summary(entries)
      assert_stable!(entries, %w[generated_bytes yjit_enabled rubyopt_sha256])
      elapsed = entries.map { |entry| entry.fetch("elapsed_ms") }
      {
        observations: { elapsed_ms: elapsed },
        statistics: { elapsed_ms: ComparisonStatistics.describe(elapsed) },
        generated_bytes: entries.first.fetch("generated_bytes")
      }
    end

    def runtime_summary(entries)
      assert_stable!(
        entries,
        %w[
          generated_bytes result_sha256 result_sequence_sha256 result_sequence_length
          runtime_backend yjit_enabled rubyopt_sha256
        ]
      )
      elapsed = entries.map { |entry| entry.fetch("elapsed_ms_per_parse") }
      allocations = entries.map { |entry| entry.fetch("allocated_objects_per_parse") }
      reference = entries.first
      {
        observations: { elapsed_ms_per_parse: elapsed, allocated_objects_per_parse: allocations },
        statistics: {
          elapsed_ms_per_parse: ComparisonStatistics.describe(elapsed),
          allocated_objects_per_parse: ComparisonStatistics.describe(allocations)
        },
        generated_bytes: reference.fetch("generated_bytes"),
        result_sha256: reference.fetch("result_sha256"),
        result_sequence_sha256: reference.fetch("result_sequence_sha256"),
        result_sequence_length: reference.fetch("result_sequence_length"),
        runtime_backend: reference.fetch("runtime_backend")
      }
    end

    def generation_comparison(summaries, options, identifier)
      {
        elapsed_ms: compare_metric(summaries, %i[observations elapsed_ms], options, identifier, "generation"),
        generated_bytes: size_comparison(summaries)
      }
    end

    def runtime_comparison(summaries, options, identifier, scenario)
      {
        elapsed_ms_per_parse: compare_metric(
          summaries, %i[observations elapsed_ms_per_parse], options, identifier, "#{scenario}:elapsed"
        ),
        allocated_objects_per_parse: compare_metric(
          summaries, %i[observations allocated_objects_per_parse], options, identifier, "#{scenario}:allocations"
        ),
        generated_bytes: size_comparison(summaries),
        result_equivalent: summaries.values.map { |value| value.fetch(:result_sha256) }.uniq.one?,
        result_sequence_equivalent: summaries.values.map { |value| value.fetch(:result_sequence_sha256) }.uniq.one?
      }
    end

    def compare_metric(summaries, path, options, identifier, metric)
      values = summaries.transform_values { |summary| path.reduce(summary) { |value, key| value.fetch(key) } }
      seed = Digest::SHA256.hexdigest("#{identifier}:#{metric}").slice(0, 8).to_i(16)
      ComparisonStatistics.compare(
        values.fetch("ibex"), values.fetch("racc"), seed: seed, samples: options.fetch(:bootstrap_samples)
      )
    end

    def size_comparison(summaries)
      ibex = summaries.fetch("ibex").fetch(:generated_bytes)
      racc = summaries.fetch("racc").fetch(:generated_bytes)
      { ibex_bytes: ibex, racc_bytes: racc, ibex_to_racc_ratio: (ibex.to_f / racc).round(6) }
    end

    def assert_stable!(entries, keys)
      keys.each do |key|
        values = entries.map { |entry| entry.fetch(key) }.uniq
        raise "#{key} changed between isolated runs" unless values.length == 1
      end
    end

    def assert_equivalent!(observations)
      entries = observations.except("cold_generation").values.flat_map(&:values).flatten(1)
      %w[result_sha256 result_sequence_sha256 result_sequence_length].each do |key|
        values = entries.map { |entry| entry.fetch(key) }.uniq
        raise "#{key} differs across implementations or lifecycles" unless values.length == 1
      end
    end

    def configuration(options)
      {
        runs: options.fetch(:runs),
        warmup_workloads: options.fetch(:warmup),
        measured_workloads: options.fetch(:iterations),
        probe_workloads: options.fetch(:probe_iterations),
        bootstrap_samples: options.fetch(:bootstrap_samples),
        expected_racc_backend: options.fetch(:expected_racc_backend),
        process_order: "alternating_per_run",
        runtime_scope: "end_to_end_lexer_inclusive",
        parser_lifecycles: %w[reuse new_instance],
        allow_dirty_checkouts: options.fetch(:allow_dirty)
      }
    end

    def repository_metadata(workload, checkout)
      checkout.except(:root).merge(
        url: workload.fetch("repository_url"),
        expected_revision: workload.fetch("revision"),
        grammar_path: workload.fetch("grammar_path"),
        dependency_definition_path: workload.fetch("dependency_definition_path")
      )
    end

    def workload_metadata(workload)
      {
        id: workload.fetch("workload_id"),
        driver: workload.fetch("driver"),
        input_count: workload.fetch("inputs").length,
        inputs_sha256: Digest::SHA256.hexdigest(JSON.generate(workload.fetch("inputs")))
      }
    end

    def command_metadata(options, identifier)
      generation = PublicComparisonWorker::IMPLEMENTATIONS.to_h do |implementation|
        command = PublicComparisonWorker.command_for(implementation, "<generated-output>", "<public-grammar>")
        [implementation.to_sym, command.map { |part| part.gsub(PublicComparisonWorker::ROOT, "<repository>") }]
      end
      {
        generation: generation,
        worker: PublicPerformanceComparison.worker_command(
          "<implementation>", "<scenario>", identifier, "<checkout>", options
        ).map { |part| part.gsub(PublicComparisonWorker::ROOT, "<repository>") }
      }
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
