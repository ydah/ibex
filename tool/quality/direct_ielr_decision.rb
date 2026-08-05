# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "json_schemer"
require "open3"

module Ibex
  module Quality
    # Validates the I001 decision, its H005/V001 evidence, and its provenance.
    class DirectIELRDecision # rubocop:disable Metrics/ClassLength -- one closed decision record and evidence contract.
      GO_CONDITIONS = {
        "representative-practical-canonical-cost" => "not_satisfied",
        "ielr-required-by-representative-grammars" => "not_satisfied",
        "algorithm-and-specification-owner" => "not_satisfied",
        "noncanonical-verification-plan" => "not_satisfied",
        "maintenance-budget-accepted" => "not_satisfied"
      }.freeze
      NO_GO_CONDITIONS = {
        "no-real-ielr-required-workload" => "satisfied",
        "canonical-lr1-completes-within-current-measured-budget" => "satisfied",
        "lr1-or-grammar-rewrite-is-simpler" => "not_assessable",
        "verifier-still-enumerates-full-canonical-collection" => "satisfied",
        "only-state-count-benefit" => "satisfied"
      }.freeze
      TRIGGERS = %w[
        representative-real-grammars material-canonical-cost meaningful-ielr-need
        scale-independent-verification algorithm-and-specification-owner maintenance-budget
      ].freeze
      SOURCE_IDS = %w[
        h005-human-report h005-machine-evidence h005-evidence-schema
        v001-trust-boundary v001-reference-collection v001-verifier
      ].freeze

      def initialize(root: File.expand_path("../..", __dir__), dossier: nil, output: $stdout)
        @root = File.expand_path(root)
        @dossier = dossier || File.join(@root, "tool/quality/evidence/direct-ielr-decision-v1.json")
        @output = output
      end

      def verify!
        document = JSON.parse(File.binread(@dossier))
        validate_schema!(document)
        validate_decision!(document)
        profile = validate_profile!(document)
        validate_verifier_boundary!(document)
        validate_provenance!(document, profile)
        @output.puts "I001 direct IELR NO-GO dossier matches H005 and V001 evidence"
        document
      end

      private

      def validate_schema!(document)
        path = File.join(@root, "schema/direct-ielr-decision-v1.schema.json")
        errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(document).to_a
        raise "direct IELR decision violates schema: #{JSON.generate(errors)}" unless errors.empty?
      end

      def validate_decision!(document)
        decision = document.fetch("decision")
        Date.iso8601(decision.fetch("date"))
        validate_finality!(decision)

        raise "I002 must remain blocked by the I001 NO-GO" if document.fetch("follow_on").values.any?

        validate_policy!(document.fetch("policy"))
        validate_triggers!(document.fetch("reconsideration_triggers"))
        validate_legal_provenance!(document.fetch("legal_provenance"))
      rescue Date::Error
        raise "direct IELR decision date is not an ISO 8601 date"
      end

      def validate_finality!(decision)
        finalized = decision.values_at("value", "status", "basis", "review_state")
        expected = %w[NO-GO final_no_go repository_evidence validated]
        raise "direct IELR decision is not a finalized evidence-based NO-GO" unless finalized == expected
      end

      def validate_policy!(policy)
        verify_conditions!(policy.fetch("go_conditions"), GO_CONDITIONS, "GO")
        verify_conditions!(policy.fetch("no_go_conditions"), NO_GO_CONDITIONS, "NO-GO")
        raise "NO-GO has no satisfied condition" unless NO_GO_CONDITIONS.value?("satisfied")
      end

      def validate_triggers!(records)
        triggers = records.map { |item| item.fetch("id") }
        raise "direct IELR reconsideration trigger inventory drift" unless triggers == TRIGGERS
      end

      def validate_legal_provenance!(legal)
        return if legal.fetch("design_lineage") == "independent_design_from_papers_and_specifications" &&
                  legal.fetch("permitted_design_inputs") == %w[papers specifications] &&
                  !legal.fetch("gpl_implementation_source_used") &&
                  !legal.fetch("gpl_implementation_source_translated")

        raise "direct IELR legal provenance permits GPL implementation lineage"
      end

      def verify_conditions!(conditions, expected, label)
        actual = conditions.to_h { |condition| condition.values_at("id", "status") }
        raise "direct IELR #{label} condition inventory drift" unless actual == expected
      end

      def validate_profile!(document)
        path = File.join(@root, "tool/profile/evidence/construction-profile-v1.json")
        profile = JSON.parse(File.binread(path))
        direct = profile.fetch("decisions").find { |item| item.fetch("feature") == "direct-ielr" }
        raise "H005 direct IELR decision is missing" unless direct
        raise "H005 direct IELR decision is not NO-GO" unless direct.fetch("decision") == "NO-GO"

        expected_thresholds = {
          "representative-real-profiles" => ["1", false],
          "real-ielr-need" => ["0 structural candidates; 0 semantically reviewed", false],
          "verifier-tcb" => ["complete at 5cf20f6", true],
          "scale-independent-verification" =>
            ["not satisfied: default and strict IELR verification enumerate canonical LR(1)", false]
        }
        thresholds = direct.fetch("thresholds").to_h do |item|
          [item.fetch("id"), item.values_at("observed", "satisfied")]
        end
        raise "H005 direct IELR threshold evidence drift" unless thresholds == expected_thresholds

        validate_profile_observations!(document, profile)
        profile
      end

      def validate_profile_observations!(document, profile)
        observations = document.fetch("observations")
        workloads = profile.fetch("cohorts").flat_map { |cohort| cohort.fetch("workloads") }
        validate_workload_counts!(observations, workloads)
        validate_frontend_observations!(observations, workloads)
        validate_evidence_scope!(observations)
      end

      def validate_workload_counts!(observations, workloads)
        measured_real = workloads.count do |workload|
          measured_real_workload?(workload)
        end
        expected_real = observations.fetch("measured_real_grammars")
        raise "measured real grammar count drift" unless expected_real == measured_real

        public_runs = workloads.count do |workload|
          workload.fetch("classification") == "public_real" && !workload.fetch("runs").empty?
        end
        expected_public = observations.fetch("verified_public_checkouts")
        raise "verified public checkout count drift" unless expected_public == public_runs
      end

      def measured_real_workload?(workload)
        workload.fetch("classification").end_with?("_real") &&
          workload.fetch("runs").any? { |run| run.fetch("status") == "completed" }
      end

      def validate_frontend_observations!(observations, workloads)
        frontend = workloads.find { |workload| workload.fetch("id") == "ibex-frontend" }
        ielr = frontend.fetch("runs").find { |run| run.fetch("algorithm") == "ielr" }
        expected_frontend = {
          "id" => "ibex-frontend",
          "lr0_states" => measured(ielr, "lr0_states"),
          "lr0_items" => measured(ielr, "lr0_items"),
          "canonical_states" => measured(ielr, "canonical_states"),
          "canonical_items" => measured(ielr, "canonical_items"),
          "final_states" => measured(ielr, "final_states"),
          "unresolved_ielr_conflicts" => ielr.fetch("conflicts").values.sum
        }
        raise "ibex frontend construction observations drift" unless
          observations.fetch("current_real_workload") == expected_frontend
      end

      def validate_evidence_scope!(observations)
        zero_fields = %w[real_ielr_required_workloads semantically_reviewed_conflict_removals]
        raise "unsubstantiated real IELR need" unless zero_fields.all? { |field| observations.fetch(field).zero? }

        scale = observations.fetch("canonical_scale_cost")
        raise "canonical scale cost must remain unresolved" unless scale.fetch("status") == "unresolved"
      end

      def measured(run, field)
        observation = run.fetch("structural").fetch(field)
        raise "H005 #{field} is no longer measured" unless observation.fetch("status") == "measured"

        observation.fetch("value")
      end

      def validate_verifier_boundary!(document)
        source = File.binread(File.join(@root, "docs/verifier-trust-boundary.md"))
        required = [
          "Default and strict both construct the algorithm-specific reference",
          "LALR(1), IELR(1), and LR(1) verification enumerate the canonical LR(1)",
          "does not establish conflict preservation, canonical state correspondence, or\nsplit witnesses",
          "| `ielr-adequacy` | Conflict preservation"
        ]
        missing = required.reject { |text| source.include?(text) }
        raise "V001 IELR boundary wording drift: #{missing.join(', ')}" unless missing.empty?

        gaps = document.fetch("verification_gaps")
        raise "I001 claims unsupported IELR verification" unless gaps.values.all? { |value| value == "not_verified" }
      end

      def validate_provenance!(document, profile)
        decision_revision = document.dig("decision", "revision")
        verify_revision!(decision_revision, "decision")
        identity = document.fetch("evidence_identity")
        verify_revision!(identity.fetch("v001_revision"), "V001", ancestor_of: decision_revision)
        provenance = profile.fetch("provenance")
        identity_fields = {
          "profile_capture_base_revision" => "base_revision",
          "profile_bound_paths_sha256" => "bound_paths_sha256",
          "profile_implementation_sha256" => "implementation_sha256"
        }
        identity_fields.each do |dossier_field, profile_field|
          next if identity.fetch(dossier_field) == provenance.fetch(profile_field)

          raise "H005 #{dossier_field} identity drift"
        end

        sources = identity.fetch("sources")
        raise "direct IELR evidence source inventory drift" unless sources.map { |item| item.fetch("id") } == SOURCE_IDS

        sources.each { |source| verify_source!(decision_revision, source) }
        digest = Digest::SHA256.hexdigest(JSON.generate(sources))
        raise "direct IELR evidence source digest drift" unless digest == identity.fetch("sources_sha256")
      end

      def verify_revision!(revision, label, ancestor_of: "HEAD")
        _output, status = capture("git", "cat-file", "-e", "#{revision}^{commit}")
        raise "#{label} revision is unavailable" unless status.success?

        _output, status = capture("git", "merge-base", "--is-ancestor", revision, ancestor_of)
        raise "#{label} revision is not in the reviewed history" unless status.success?
      end

      def verify_source!(revision, source)
        path = source.fetch("path")
        expected = source.fetch("sha256")
        current = File.join(@root, path)
        raise "decision evidence source is unavailable: #{path}" unless File.file?(current)
        raise "decision evidence source digest drift: #{path}" unless Digest::SHA256.file(current).hexdigest == expected

        bytes, status = capture("git", "show", "#{revision}:#{path}")
        raise "decision evidence source is unavailable at reviewed revision: #{path}" unless status.success?
        return if Digest::SHA256.hexdigest(bytes.b) == expected

        raise "decision evidence source digest drift at reviewed revision: #{path}"
      end

      def capture(*command)
        stdout, _stderr, status = Open3.capture3(*command, chdir: @root)
        [stdout, status]
      end
    end
  end
end
