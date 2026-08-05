# frozen_string_literal: true

require "digest"
require "etc"
require "json"
require "open3"
require "rbconfig"
require "timeout"
require "yaml"

module Ibex
  module Profile
    # Records structural construction costs without changing parser construction.
    # Wall time is diagnostic only; it is never interpreted as a release gate.
    class ConstructionProfiler
      ALGORITHMS = %i[lalr ielr].freeze
      STRUCTURAL_FIELDS = %i[
        lr0_states lr0_items canonical_states canonical_items final_states final_items
        final_lookahead_items propagation_edges ielr_initial_partitions ielr_final_partitions
      ].freeze

      def initialize(wall_seconds: 60.0, clock: nil, builder_factory: nil)
        raise ArgumentError, "wall_seconds must be positive" unless wall_seconds.positive?

        @wall_seconds = wall_seconds
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @builder_factory = builder_factory || lambda do |grammar, algorithm, isolated|
          LALR::Builder.new(grammar, algorithm: algorithm, entry_isolation: isolated, profile: true)
        end
      end

      def profile(grammar)
        modes = grammar.starts.length > 1 ? %w[shared isolated] : %w[shared]
        modes.product(ALGORITHMS).map do |entry_mode, algorithm|
          profile_run(grammar, algorithm, entry_mode)
        end
      end

      private

      def profile_run(grammar, algorithm, entry_mode)
        started = @clock.call
        builder = @builder_factory.call(grammar, algorithm, entry_mode == "isolated")
        automaton = Timeout.timeout(@wall_seconds) { builder.build }
        completed_run(grammar, algorithm, entry_mode, builder, automaton, elapsed(started))
      rescue Timeout::Error
        failed_run(grammar, algorithm, entry_mode, started, "limit_exceeded", "wall_time",
                   "construction exceeded the profiler wall-time limit")
      rescue NoMemoryError
        failed_run(grammar, algorithm, entry_mode, started, "resource_exhausted", "memory",
                   "Ruby raised NoMemoryError during construction")
      rescue SystemStackError
        failed_run(grammar, algorithm, entry_mode, started, "resource_exhausted", "stack",
                   "Ruby raised SystemStackError during construction")
      rescue StandardError => e
        failed_run(grammar, algorithm, entry_mode, started, "failed", "construction",
                   "#{e.class}: #{e.message}")
      end

      def completed_run(grammar, algorithm, entry_mode, builder, automaton, elapsed_seconds)
        metrics = builder.metrics || raise(Ibex::Error, "construction completed without build metrics")
        {
          "algorithm" => algorithm.to_s,
          "entry_mode" => entry_mode,
          "entries" => grammar.starts.length,
          "entry_names" => grammar.starts,
          "status" => "completed",
          "strategy" => metrics.strategy.to_s,
          "structural" => structural_metrics(metrics),
          "conflicts" => {
            "shift_reduce" => automaton.conflict_summary.fetch(:sr),
            "reduce_reduce" => automaton.conflict_summary.fetch(:rr)
          },
          "observations" => elapsed_observation(elapsed_seconds),
          "exhaustion" => { "status" => "not_observed", "resource" => nil, "limit" => nil },
          "failure" => nil
        }
      end

      def failed_run(grammar, algorithm, entry_mode, started, status, resource, message)
        {
          "algorithm" => algorithm.to_s,
          "entry_mode" => entry_mode,
          "entries" => grammar.starts.length,
          "entry_names" => grammar.starts,
          "status" => status,
          "strategy" => nil,
          "structural" => STRUCTURAL_FIELDS.to_h do |field|
            [field.to_s, unavailable("construction did not complete")]
          end,
          "conflicts" => nil,
          "observations" => elapsed_observation(elapsed(started)),
          "exhaustion" => exhaustion(status, resource),
          "failure" => { "resource" => resource, "message" => message }
        }
      end

      def structural_metrics(metrics)
        {
          "lr0_states" => measured(metrics.lr0_states),
          "lr0_items" => measured(metrics.lr0_items),
          "canonical_states" => optional(metrics.canonical_states, "canonical LR(1) was not constructed"),
          "canonical_items" => optional(metrics.canonical_items, "canonical LR(1) was not constructed"),
          "final_states" => measured(metrics.final_states),
          "final_items" => measured(metrics.final_items),
          "final_lookahead_items" => measured(metrics.final_lookahead_items),
          "propagation_edges" => optional(
            metrics.propagation_edges, "this construction path does not use direct lookahead propagation"
          ),
          "ielr_initial_partitions" => optional(
            metrics.ielr_initial_partitions, "this construction path does not run IELR partitioning"
          ),
          "ielr_final_partitions" => optional(
            metrics.ielr_final_partitions, "this construction path does not run IELR partitioning"
          )
        }
      end

      def measured(value)
        { "status" => "measured", "value" => value }
      end

      def optional(value, reason)
        value.nil? ? unavailable(reason) : measured(value)
      end

      def unavailable(reason)
        { "status" => "not_applicable", "reason" => reason }
      end

      def elapsed_observation(value)
        {
          "elapsed_seconds" => {
            "status" => "observation",
            "value" => value.round(6),
            "release_gate" => false
          }
        }
      end

      def exhaustion(status, resource)
        limit = resource == "wall_time" ? @wall_seconds : nil
        observed = %w[limit_exceeded resource_exhausted].include?(status)
        { "status" => observed ? "observed" : "not_observed", "resource" => resource, "limit" => limit }
      end

      def elapsed(started)
        @clock.call - started
      end
    end

    # Applies explicit H005 thresholds without treating timing as a gate.
    class ConstructionDecisions
      def initialize(cohorts)
        @real = cohorts.find { |cohort| cohort.fetch("kind") == "real" }.fetch("workloads")
        @synthetic = cohorts.find { |cohort| cohort.fetch("kind") == "synthetic" }.fetch("workloads")
      end

      def build
        [ielr_decision, multi_entry_decision]
      end

      private

      def ielr_decision
        profiled = @real.count { |item| item.dig("availability", "status")&.start_with?("verified_") }
        candidates = @real.count { |item| removes_conflicts?(item) }
        unavailable = @real.count do |item|
          item.fetch("classification") == "public_real" && item.dig("availability", "status") == "not_run"
        end
        decision(
          "direct-ielr", "NO-GO", [
            threshold("representative-real-profiles", "at least 2", profiled.to_s, profiled >= 2),
            threshold("real-ielr-need", "at least 2 grammars with meaningful conflicts removed",
                      "#{candidates} structural candidates; 0 semantically reviewed", false),
            threshold("verifier-tcb", "V001 complete and reviewed", "complete at 5cf20f6", true),
            threshold("scale-independent-verification", "verification avoids canonical LR(1) enumeration",
                      "not satisfied: default and strict IELR verification enumerate canonical LR(1)", false)
          ],
          "The current verifier still enumerates canonical LR(1), #{unavailable} public workloads are not run, " \
          "and no real conflict removal has semantic review; direct IELR is not justified now."
        )
      end

      def removes_conflicts?(workload)
        lalr = workload.fetch("runs").find do |run|
          run.values_at("entry_mode", "algorithm", "status") == %w[shared lalr completed]
        end
        ielr = workload.fetch("runs").find do |run|
          run.values_at("entry_mode", "algorithm", "status") == %w[shared ielr completed]
        end
        return false unless lalr && ielr

        conflict_count(lalr) > conflict_count(ielr)
      end

      def conflict_count(run)
        run.fetch("conflicts").values.sum
      end

      def multi_entry_decision
        real = @real.count { |item| item.dig("entries", "count").to_i > 1 }
        synthetic = @synthetic.count { |item| item.dig("entries", "count").to_i > 1 }
        decision(
          "direct-multi-entry", "MORE DATA", [
            threshold("representative-real-multi-entry", "at least 2", real.to_s, real >= 2),
            threshold("synthetic-shared-isolated-coverage", "at least 1", synthetic.to_s, synthetic >= 1),
            threshold("practical-current-cost", "state/item exhaustion or >=2x structural overhead on real inputs",
                      "not observed on a real multi-entry workload", false)
          ],
          "The shared-versus-isolated path is measurable on a synthetic fixture, but the registry has no real " \
          "multi-entry workload and timing observations are not decision gates."
        )
      end

      def threshold(id, target, observed, satisfied)
        { "id" => id, "target" => target, "observed" => observed, "satisfied" => satisfied }
      end

      def decision(feature, outcome, thresholds, reason)
        {
          "feature" => feature,
          "decision" => outcome,
          "thresholds" => thresholds,
          "reason" => reason,
          "counterevidence_required" => counterevidence(feature)
        }
      end

      def counterevidence(feature)
        if feature == "direct-ielr"
          return [
            "verified real grammars show material canonical collection cost",
            "IELR removes semantically meaningful conflicts on those grammars",
            "a bounded verification plan avoids mandatory canonical enumeration",
            "an owner accepts the specification and maintenance budget"
          ]
        end

        [
          "verified real multi-entry grammars show material shared construction cost",
          "a direct construction preserves shared-entry conflict attribution",
          "an owner accepts the semantic and maintenance plan"
        ]
      end
    end

    # Captures the implementation and host identity attached to one observation.
    class ConstructionEnvironment
      IMPLEMENTATION_PATHS = %w[
        lib/ibex/lalr/build_metrics.rb
        lib/ibex/lalr/builder.rb
        lib/ibex/lalr/direct_lookaheads.rb
        lib/ibex/lalr/ielr_partition.rb
        tool/profile/construction_profiler.rb
      ].freeze

      def initialize(root)
        @root = root
      end

      def build
        revision, = capture("git", "rev-parse", "HEAD")
        status, = capture("git", "status", "--porcelain=v1", "--untracked-files=normal")
        uname = Etc.uname
        {
          "ibex_revision" => revision,
          "ibex_worktree_clean" => status.empty?,
          "implementation_sha256" => implementation_digest,
          "ruby_engine" => RUBY_ENGINE,
          "ruby_version" => RUBY_VERSION,
          "ruby_patchlevel" => RUBY_PATCHLEVEL,
          "ruby_description" => RUBY_DESCRIPTION,
          "ruby_platform" => RUBY_PLATFORM,
          "rubyopt" => ENV.fetch("RUBYOPT", nil),
          "yjit_enabled" => yjit_enabled?,
          "host_os" => RbConfig::CONFIG.fetch("host_os"),
          "host_cpu" => RbConfig::CONFIG.fetch("host_cpu"),
          "kernel_name" => uname.fetch(:sysname),
          "kernel_release" => uname.fetch(:release),
          "kernel_version" => uname.fetch(:version),
          "kernel_machine" => uname.fetch(:machine),
          "logical_processors" => Etc.nprocessors
        }
      end

      private

      def implementation_digest
        digest = Digest::SHA256.new
        IMPLEMENTATION_PATHS.sort.each do |path|
          digest << path << "\0" << File.binread(File.join(@root, path)) << "\0"
        end
        digest.hexdigest
      end

      def capture(*command)
        stdout, stderr, status = Open3.capture3(*command, chdir: @root)
        raise "metadata command failed: #{stderr}#{stdout}" unless status.success?

        [stdout.strip, stderr]
      end

      def yjit_enabled?
        return false unless defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?)

        RubyVM::YJIT.enabled?
      end
    end

    # Builds the repository/public workload report and keeps source classes separate.
    class ConstructionReport
      MATRIX_REVISION = "e892ffad7d7178028dcf1c074d2db90af068d866"

      def initialize(root:, wall_seconds:, checkouts: {})
        @root = File.expand_path(root)
        @profiler = ConstructionProfiler.new(wall_seconds: wall_seconds)
        @wall_seconds = wall_seconds
        @checkouts = checkouts
        @registry = YAML.safe_load_file(File.join(@root, "docs/workloads.yml"), aliases: false)
      end

      def build
        validate_checkout_ids!
        cohorts = [synthetic_cohort, real_cohort]
        {
          "ibex_report" => "construction_profile",
          "schema_version" => 1,
          "trust" => "internal_local_observation",
          "environment" => ConstructionEnvironment.new(@root).build,
          "measurement_policy" => measurement_policy,
          "cohorts" => cohorts,
          "decisions" => ConstructionDecisions.new(cohorts).build,
          "limitations" => limitations
        }
      end

      private

      def synthetic_cohort
        workloads = registered_workloads.select { |item| item.fetch("classification") == "repository_synthetic" }
        records = workloads.map { |item| local_record(item) }
        records << matrix_record
        { "kind" => "synthetic", "workloads" => records.sort_by { |item| item.fetch("id") } }
      end

      def real_cohort
        local = registered_workloads.select { |item| item.fetch("classification") == "repository_real" }
                                    .map { |item| local_record(item) }
        public_records = registered_workloads.select { |item| item.fetch("classification") == "public_real" }
                                             .map { |item| public_record(item) }
        { "kind" => "real", "workloads" => (local + public_records).sort_by { |item| item.fetch("id") } }
      end

      def registered_workloads
        @registry.fetch("workloads")
      end

      def validate_checkout_ids!
        known = registered_workloads.filter_map do |item|
          item.dig("source_binding", "id") if item.fetch("classification") == "public_real"
        end
        unknown = @checkouts.keys - known
        raise ArgumentError, "unknown public workload checkout: #{unknown.sort.join(', ')}" unless unknown.empty?
      end

      def local_record(item)
        path = item.dig("grammar", "path")
        source = File.binread(File.join(@root, path))
        verify_digest!(item.fetch("id"), source, item.dig("grammar", "sha256"))
        workload_record(item, source, path, "verified_repository_source")
      end

      def matrix_record
        source = matrix_source
        item = {
          "id" => "matrix-multi-entry",
          "classification" => "repository_synthetic",
          "revision" => MATRIX_REVISION,
          "grammar" => {
            "identity" => "Representative matrix multi-entry diagnostic",
            "path" => "test/support/matrix_runner.rb#grammar_source(entries=multi,cst=off,locations=off)",
            "sha256" => Digest::SHA256.hexdigest(source)
          }
        }
        workload_record(item, source, "matrix-multi-entry.y", "verified_generated_fixture",
                        registry_status: "unregistered_diagnostic")
      end

      def public_record(item)
        binding = item.dig("source_binding", "id")
        checkout = @checkouts[binding]
        return unavailable_public_record(item, binding) unless checkout

        require_relative "../../benchmark/support/public_workload_manifest"
        manifest = BenchmarkSupport::PublicWorkloadManifest.new(File.join(@root, "benchmark/public_workloads.json"))
        metadata = manifest.verify_checkout(binding, checkout, allow_dirty: false)
        path = item.dig("grammar", "path")
        source = File.binread(File.join(metadata.fetch(:root), path))
        workload_record(item, source, path, "verified_public_checkout")
      end

      def unavailable_public_record(item, binding, reason = nil)
        reason ||= "no verified checkout supplied; pass --checkout #{binding}=PATH to collect this observation"
        record_identity(item).merge(
          "registry_status" => "registered",
          "availability" => { "status" => "not_run", "reason" => reason },
          "entries" => nil,
          "runs" => []
        )
      end

      def workload_record(item, source, parser_path, availability, registry_status: "registered")
        mode = source.include?("pragma extended") ? :extended : :default
        ast = Frontend::Parser.new(source, file: parser_path, mode: mode).parse
        grammar = Normalizer.new(ast, mode: mode).normalize
        record_identity(item).merge(
          "registry_status" => registry_status,
          "availability" => { "status" => availability, "reason" => nil },
          "entries" => { "count" => grammar.starts.length, "names" => grammar.starts },
          "runs" => @profiler.profile(grammar)
        )
      end

      def record_identity(item)
        {
          "id" => item.fetch("id"),
          "classification" => item.fetch("classification"),
          "grammar" => {
            "identity" => item.dig("grammar", "identity"),
            "path" => item.dig("grammar", "path"),
            "revision" => item.fetch("revision"),
            "sha256" => item.dig("grammar", "sha256")
          }
        }
      end

      def verify_digest!(id, source, expected)
        actual = Digest::SHA256.hexdigest(source)
        raise "#{id}: grammar digest drift (expected #{expected}, got #{actual})" unless actual == expected
      end

      def matrix_source
        <<~GRAMMAR
          class MatrixParser
          pragma extended

          start document atom
          token NUM PLUS
          lexer
            skip /[[:space:]]+/
            NUM /[0-9]+/ { |text| Integer(text, 10) }
            PLUS '+'
          end
          rule
          document: expression {  result = val[0] }
          atom: NUM {  result = val[0] }
          expression: NUM {  result = val[0] }
                    | expression PLUS NUM {  result = val[0] + val[2] }
          end
        GRAMMAR
      end

      def measurement_policy
        {
          "wall_seconds_per_run" => @wall_seconds,
          "wall_time_role" => "observation_only",
          "state_limit" => { "status" => "not_supported", "reason" => "current builders expose no state budget" },
          "memory_limit" => { "status" => "not_supported", "reason" => "no portable per-build Ruby heap limit" },
          "peak_retained_objects" => {
            "status" => "not_measured",
            "reason" => "GC live-slot deltas are not a reproducible peak-retained-object measurement"
          },
          "item_counting" => {
            "lr0_items" => "LR(0) core item occurrences across distinct LR(0) cores",
            "canonical_items" => "LR(1) item triples across canonical states",
            "final_items" => "core item occurrences after merge or partition",
            "final_lookahead_items" => "lookahead memberships across final core items"
          }
        }
      end

      def limitations
        [
          "A timeout or resource failure is evidence of an observed bound, not a negative proof of correctness.",
          "Elapsed time varies by host and is not a release gate or a committed performance golden.",
          "Peak retained objects are not reported because the current Ruby VM interface cannot measure them " \
          "reproducibly.",
          "Unavailable public workloads retain registry identity only and contribute no construction measurements.",
          "V001 records that current IELR verification enumerates canonical LR(1) in default and strict modes.",
          "This profile implements neither direct IELR nor direct shared multi-entry construction."
        ]
      end
    end
  end
end
