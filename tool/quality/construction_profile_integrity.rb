# frozen_string_literal: true

require "digest"
require "open3"

module Ibex
  module Quality
    # Reconstructs the source snapshot and validates host-observation integrity.
    class ConstructionProfileProvenance
      def initialize(root:, document:)
        @root = root
        @document = document
        @provenance = document.fetch("provenance")
      end

      def verify!
        verify_base_revision!
        verify_observation_digests!
        bindings = verify_bound_paths!
        verify_capture_status!(bindings)
        verify_implementation_digest!(bindings)
      end

      private

      def verify_base_revision!
        revision = @provenance.fetch("base_revision")
        _output, status = capture("git", "cat-file", "-e", "#{revision}^{commit}")
        raise "construction profile base revision is unavailable" unless status.success?

        _output, status = capture("git", "merge-base", "--is-ancestor", revision, "HEAD")
        raise "construction profile base revision is not an ancestor of HEAD" unless status.success?
      end

      def verify_observation_digests!
        verify_digest!("environment observation", @document.fetch("environment"),
                       @provenance.fetch("environment_observation_sha256"))
        verify_digest!("measurement policy", @document.fetch("measurement_policy"),
                       @provenance.fetch("measurement_policy_sha256"))
      end

      def verify_bound_paths!
        bindings = @provenance.fetch("bound_paths")
        expected = Profile::ConstructionProvenance::BOUND_PATHS.sort
        actual = bindings.map { |item| item.fetch("path") }
        raise "construction profile bound path inventory drift" unless actual == expected

        bindings.each { |item| verify_binding!(item) }
        verify_digest!("bound paths", bindings, @provenance.fetch("bound_paths_sha256"))
        bindings
      end

      def verify_binding!(item)
        path = item.fetch("path")
        current_digest = Digest::SHA256.file(File.join(@root, path)).hexdigest
        raise "construction profile bound source drift: #{path}" unless current_digest == item.fetch("sha256")

        base_bytes = git_object(@provenance.fetch("base_revision"), path)
        base_digest = Digest::SHA256.hexdigest(base_bytes) if base_bytes
        raise "construction profile base source digest drift: #{path}" unless base_digest == item.fetch("base_sha256")

        expected_state = if base_digest.nil?
                           "untracked"
                         else
                           base_digest == current_digest ? "base" : "modified"
                         end
        raise "construction profile Git state drift: #{path}" unless item.fetch("git_state") == expected_state
      rescue Errno::ENOENT
        raise "construction profile bound source is missing: #{path}"
      end

      def verify_capture_status!(bindings)
        lines = @provenance.fetch("capture_worktree_status")
        clean = @provenance.fetch("capture_worktree_clean")
        raise "construction profile capture clean-state drift" unless clean == lines.empty?

        verify_digest!("capture worktree status", lines, @provenance.fetch("capture_worktree_status_sha256"))
        changed = bindings.reject { |item| item.fetch("git_state") == "base" }
        missing = changed.reject { |item| lines.any? { |line| line.end_with?(item.fetch("path")) } }
        raise "construction profile capture status omits bound changes" unless missing.empty?
      end

      def verify_implementation_digest!(bindings)
        paths = Profile::ConstructionProvenance::IMPLEMENTATION_PATHS
        selected = bindings.select { |item| paths.include?(item.fetch("path")) }
                           .map { |item| item.slice("path", "sha256") }
        verify_digest!("implementation", selected, @provenance.fetch("implementation_sha256"))
      end

      def verify_digest!(label, value, expected)
        actual = Profile::ConstructionDigest.sha256(value)
        raise "construction profile #{label} digest drift" unless actual == expected
      end

      def git_object(revision, path)
        output, status = capture("git", "show", "#{revision}:#{path}")
        output.b if status.success?
      end

      def capture(*command)
        stdout, _stderr, status = Open3.capture3(*command, chdir: @root)
        [stdout, status]
      end
    end

    # Validates relationships that JSON Schema cannot express across records.
    class ConstructionProfileSemantics
      def initialize(document)
        @document = document
      end

      def verify!
        workloads = @document.fetch("cohorts").flat_map { |cohort| cohort.fetch("workloads") }
        identifiers = workloads.map { |workload| workload.fetch("id") }
        raise "construction profile workload identifiers are not unique" unless identifiers.uniq == identifiers

        workloads.each { |workload| verify_workload!(workload) }
      end

      private

      def verify_workload!(workload)
        entries = workload.fetch("entries")
        return if entries.nil?

        count = entries.fetch("count")
        names = entries.fetch("names")
        raise "#{workload.fetch('id')}: entry count does not match names" unless count == names.length

        expected_runs = if count > 1
                          [%w[shared lalr], %w[shared ielr], %w[isolated lalr], %w[isolated ielr]]
                        else
                          [%w[shared lalr], %w[shared ielr]]
                        end
        runs = workload.fetch("runs")
        actual_runs = runs.map { |run| run.values_at("entry_mode", "algorithm") }
        raise "#{workload.fetch('id')}: construction run matrix drift" unless actual_runs == expected_runs

        runs.each { |run| verify_run_entries!(workload.fetch("id"), run, count, names) }
      end

      def verify_run_entries!(identifier, run, count, names)
        return if run.fetch("entries") == count && run.fetch("entry_names") == names

        raise "#{identifier}: workload entries do not match construction run entries"
      end
    end
  end
end
