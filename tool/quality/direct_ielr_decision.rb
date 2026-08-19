# frozen_string_literal: true

require "date"
require "json"
require "json_schemer"
require_relative "direct_ielr_document"
require_relative "direct_ielr_provenance"

module Ibex
  module Quality
    # Validates the semantic I001 decision. Reviewed Git provenance is handled
    # by DirectIELRProvenance so wording changes do not require policy copies.
    class DirectIELRDecision
      GO_CONDITION_IDS = %w[
        representative-practical-canonical-cost
        ielr-required-by-representative-grammars
        algorithm-and-specification-owner
        noncanonical-verification-plan
        maintenance-budget-accepted
      ].freeze
      NO_GO_CONDITION_IDS = %w[
        no-real-ielr-required-workload
        canonical-lr1-completes-within-current-measured-budget
        lr1-or-grammar-rewrite-is-simpler
        verifier-still-enumerates-full-canonical-collection
        only-state-count-benefit
      ].freeze
      TRIGGER_IDS = %w[
        representative-real-grammars material-canonical-cost meaningful-ielr-need
        scale-independent-verification algorithm-and-specification-owner maintenance-budget
      ].freeze

      def initialize(root: File.expand_path("../..", __dir__), dossier: nil, output: $stdout)
        @root = File.expand_path(root)
        @canonical_dossier = dossier.nil?
        @dossier = dossier || File.join(@root, "tool/quality/evidence/direct-ielr-decision-v1.json")
        @output = output
      end

      def verify!
        document = JSON.parse(File.binread(@dossier))
        provenance = DirectIELRProvenance.new(root: @root, dossier: @dossier)
        provenance.verify_repository_history!
        validate_schema!(document)
        validate_decision!(document)
        profile = validate_profile!(document)
        validate_verifier_boundary!(document)
        provenance.verify!(document, profile)
        validate_documentation!(document) if canonical_dossier?
        @output.puts "I001 direct IELR NO-GO dossier matches H005 and V001 evidence"
        document
      end

      # Useful to documentation generation and focused policy tests: validate
      # meaning without requiring a full Git checkout.
      def verify_semantics!(document)
        validate_schema!(document)
        validate_decision!(document)
        profile = validate_profile!(document)
        validate_verifier_boundary!(document)
        [document, profile]
      end

      private

      def validate_schema!(document)
        path = File.join(@root, "schema/direct-ielr-decision-v1.schema.json")
        errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(document).to_a
        raise "direct IELR decision violates schema: #{JSON.generate(errors)}" unless errors.empty?
      end

      def canonical_dossier?
        @canonical_dossier
      end

      def validate_documentation!(document)
        path = File.join(@root, DirectIELRDocument::PATH)
        expected = DirectIELRDocument.render(document)
        raise "direct IELR public document is stale; regenerate it from the dossier" unless
          File.binread(path) == expected
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
        verify_condition_ids!(policy.fetch("go_conditions"), GO_CONDITION_IDS, "GO")
        verify_condition_ids!(policy.fetch("no_go_conditions"), NO_GO_CONDITION_IDS, "NO-GO")
        go_satisfied = policy.fetch("go_conditions").any? { |condition| condition.fetch("status") == "satisfied" }
        raise "direct IELR GO condition inventory drift" if go_satisfied
        no_go_satisfied = policy.fetch("no_go_conditions").any? { |condition| condition.fetch("status") == "satisfied" }
        raise "NO-GO has no satisfied condition" unless no_go_satisfied
      end

      def validate_triggers!(records)
        actual = records.map { |item| item.fetch("id") }
        raise "direct IELR reconsideration trigger inventory drift" unless actual == TRIGGER_IDS
        raise "direct IELR reconsideration triggers are duplicated" unless actual.uniq == actual
      end

      def validate_legal_provenance!(legal)
        return if legal.fetch("design_lineage") == "independent_design_from_papers_and_specifications" &&
                  legal.fetch("permitted_design_inputs") == %w[papers specifications] &&
                  !legal.fetch("gpl_implementation_source_used") &&
                  !legal.fetch("gpl_implementation_source_translated")

        raise "direct IELR legal provenance permits GPL implementation lineage"
      end

      def verify_condition_ids!(conditions, expected, label)
        actual = conditions.map { |condition| condition.fetch("id") }
        raise "direct IELR #{label} condition inventory drift" unless actual == expected
        raise "direct IELR #{label} conditions are duplicated" unless actual.uniq == actual
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
          "verifier-tcb" => ["complete at #{DirectIELRProvenance::V001_REVISION[0, 7]}", true],
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
        source = File.binread(File.join(@root, "docs/policy/verifier-trust-boundary.md"))
        required = [
          "Default and strict both construct the algorithm-specific reference",
          "LALR(1), IELR(1), and LR(1) verification enumerate the canonical LR(1)",
          "It does not establish conflict preservation,\ncanonical state correspondence, or split witnesses",
          "| `ielr-adequacy` | Unbounded language equivalence"
        ]
        missing = required.reject { |text| source.include?(text) }
        raise "V001 IELR boundary wording drift: #{missing.join(', ')}" unless missing.empty?

        gaps = document.fetch("verification_gaps")
        raise "I001 claims unsupported IELR verification" unless gaps.values.all? { |value| value == "not_verified" }
      end

    end
  end
end
