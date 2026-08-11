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
        "representative-practical-canonical-cost" => {
          "status" => "not_satisfied",
          "observed" => "one measured real grammar; at least two representative real grammars are required"
        }.freeze,
        "ielr-required-by-representative-grammars" => {
          "status" => "not_satisfied",
          "observed" => "zero real IELR-required workloads and zero semantically reviewed conflict removals"
        }.freeze,
        "algorithm-and-specification-owner" => {
          "status" => "not_satisfied", "observed" => "no accepted owner is recorded"
        }.freeze,
        "noncanonical-verification-plan" => {
          "status" => "not_satisfied",
          "observed" =>
            "no accepted scale-independent verification plan; current verification requires full canonical LR(1)"
        }.freeze,
        "maintenance-budget-accepted" => {
          "status" => "not_satisfied", "observed" => "no accepted maintenance budget is recorded"
        }.freeze
      }.freeze
      NO_GO_CONDITIONS = {
        "no-real-ielr-required-workload" => {
          "status" => "satisfied", "observed" => "zero real workloads currently require IELR"
        }.freeze,
        "canonical-lr1-completes-within-current-measured-budget" => {
          "status" => "satisfied",
          "observed" =>
            "the one measured real grammar completes canonical LR(1) without observed exhaustion; " \
            "no broader budget claim is made"
        }.freeze,
        "lr1-or-grammar-rewrite-is-simpler" => {
          "status" => "not_assessable",
          "observed" => "there is no concrete real conflict case on which to compare alternatives"
        }.freeze,
        "verifier-still-enumerates-full-canonical-collection" => {
          "status" => "satisfied",
          "observed" => "default and strict ielr1 verification both enumerate full canonical LR(1)"
        }.freeze,
        "only-state-count-benefit" => {
          "status" => "satisfied",
          "observed" =>
            "no semantic conflict-removal benefit is established; structural state and item counts alone do not " \
            "justify direct IELR"
        }.freeze
      }.freeze
      TRIGGERS = {
        "representative-real-grammars" => "at least two verified representative real grammars",
        "material-canonical-cost" =>
          "material canonical state or item cost, or observed bounded exhaustion, on those grammars",
        "meaningful-ielr-need" =>
          "IELR removes semantically reviewed meaningful conflicts on those grammars",
        "scale-independent-verification" =>
          "a bounded verification plan does not make full canonical LR(1) enumeration mandatory",
        "algorithm-and-specification-owner" => "an identified owner accepts the algorithm and specification",
        "maintenance-budget" =>
          "the ongoing implementation, verification, review, and maintenance budget is accepted"
      }.freeze
      SOURCES = {
        "h005-human-report" => {
          "path" => "docs/construction-profiling.md",
          "role" => "H005 thresholds, observations, NO-GO rationale, and reconsideration evidence"
        }.freeze,
        "h005-machine-evidence" => {
          "path" => "tool/profile/evidence/construction-profile-v1.json",
          "role" => "machine-readable workload measurements, thresholds, decision, and capture provenance"
        }.freeze,
        "h005-evidence-schema" => {
          "path" => "schema/construction-profile-v1.schema.json", "role" => "closed H005 evidence contract"
        }.freeze,
        "v001-trust-boundary" => {
          "path" => "docs/verifier-trust-boundary.md",
          "role" => "verifier reference cost, assurance boundary, and explicit IELR non-goals"
        }.freeze,
        "v001-reference-collection" => {
          "path" => "lib/ibex/verify/reference_collection.rb",
          "role" => "independent reference collection implementation reviewed by V001"
        }.freeze,
        "v001-verifier" => {
          "path" => "lib/ibex/verify/verifier.rb", "role" => "current verifier checks reviewed by V001"
        }.freeze
      }.freeze
      DECISION_REVISION = "3f85ef193fbd6f8db84a56b809879232faf52c9b"
      DECISION_REVISION_ROLE = "reviewed repository evidence immediately before dossier publication"
      DECISION_DATE = "2026-08-11"
      DOSSIER_REVISION = "c52699768bb8f00ead965a2adc1e11611524877b"
      DOSSIER_PATH = "tool/quality/evidence/direct-ielr-decision-v1.json"
      DOSSIER_DIGEST = "5a7ba780cad269854f4ebee534149116aa302f69386d81a7e30b705257084cb4"
      V001_REVISION = "c7e5cad89ccd00591f3127fdb76a789bbeb202ab"
      V001_PARENT_REVISION = "2d86d52ef92c2b07046c05f4fd55c32a1d6400a9"
      V001_SOURCE_DIGESTS = {
        "docs/verifier-trust-boundary.md" => "12568cd0e22a291a3d1466e537c32062fc490fd4bcb6bc886971b78f1aefbe46",
        "lib/ibex/verify/reference_collection.rb" => "d07e900652c61ddd942380d49edce0a3c811605cd82490c1e0e6db54010746fb",
        "lib/ibex/verify/verifier.rb" => "66efb73edf90d5466e102ea756c5b36e645ea6f5a780250b0b056dbfe34a80a3"
      }.freeze

      def initialize(root: File.expand_path("../..", __dir__), dossier: nil, output: $stdout)
        @root = File.expand_path(root)
        @dossier = dossier || File.join(@root, "tool/quality/evidence/direct-ielr-decision-v1.json")
        @output = output
      end

      def verify!
        validate_repository_history!
        document = JSON.parse(File.binread(@dossier))
        validate_schema!(document)
        validate_decision!(document)
        profile = validate_profile!(document)
        validate_verifier_boundary!(document)
        validate_provenance!(document, profile)
        validate_dossier_identity!
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
        raise "decision date identity drift" unless decision.fetch("date") == DECISION_DATE
        raise "decision revision identity drift" unless decision.fetch("revision") == DECISION_REVISION
        raise "decision revision role drift" unless decision.fetch("revision_role") == DECISION_REVISION_ROLE
      end

      def validate_policy!(policy)
        verify_conditions!(policy.fetch("go_conditions"), GO_CONDITIONS, "GO")
        verify_conditions!(policy.fetch("no_go_conditions"), NO_GO_CONDITIONS, "NO-GO")
        raise "NO-GO has no satisfied condition" unless
          NO_GO_CONDITIONS.values.any? { |condition| condition.fetch("status") == "satisfied" }
      end

      def validate_triggers!(records)
        triggers = records.to_h do |item|
          [item.fetch("id"), item.fetch("required_evidence")]
        end
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
        actual = conditions.to_h do |condition|
          [condition.fetch("id"), condition.slice("status", "observed")]
        end
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
          "verifier-tcb" => ["complete at #{V001_REVISION[0, 7]}", true],
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
          "It does not establish conflict preservation,\ncanonical state correspondence, or split witnesses",
          "| `ielr-adequacy` | Unbounded language equivalence"
        ]
        missing = required.reject { |text| source.include?(text) }
        raise "V001 IELR boundary wording drift: #{missing.join(', ')}" unless missing.empty?

        gaps = document.fetch("verification_gaps")
        raise "I001 claims unsupported IELR verification" unless gaps.values.all? { |value| value == "not_verified" }
      end

      def validate_provenance!(document, profile)
        decision_revision = document.dig("decision", "revision")
        verify_revision!(decision_revision, "decision")
        verify_dossier_parent!(decision_revision)
        identity = document.fetch("evidence_identity")
        v001_revision = identity.fetch("v001_revision")
        raise "V001 revision identity drift" unless v001_revision == V001_REVISION

        verify_revision!(v001_revision, "V001", ancestor_of: decision_revision)
        verify_v001_sources!
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
        source_identities = sources.to_h do |source|
          [source.fetch("id"), source.slice("path", "role")]
        end
        raise "direct IELR evidence source identity drift" unless source_identities == SOURCES

        sources.each { |source| verify_source!(decision_revision, source) }
        digest = Digest::SHA256.hexdigest(JSON.generate(sources))
        raise "direct IELR evidence source digest drift" unless digest == identity.fetch("sources_sha256")
      end

      def verify_dossier_parent!(decision_revision)
        verify_revision!(DOSSIER_REVISION, "dossier")
        _output, status = capture("git", "merge-base", "--is-ancestor", decision_revision, DOSSIER_REVISION)
        raise "decision revision is not an ancestor of the dossier revision" unless status.success?
      end

      def verify_v001_sources!
        parent, status = capture("git", "rev-parse", "#{V001_REVISION}^")
        raise "V001 parent revision is unavailable" unless status.success?
        raise "V001 parent revision identity drift" unless parent.strip == V001_PARENT_REVISION

        _output, status = capture("git", "cat-file", "-e", "#{V001_PARENT_REVISION}^{commit}")
        raise "V001 parent commit object is unavailable" unless status.success?

        V001_SOURCE_DIGESTS.each do |path, digest|
          bytes, status = capture("git", "show", "#{V001_REVISION}:#{path}")
          raise "V001 source is unavailable at the bound revision: #{path}" unless status.success?
          raise "V001 source identity drift at the bound revision: #{path}" unless
            Digest::SHA256.hexdigest(bytes.b) == digest
        end

        _bytes, status = capture("git", "show", "#{V001_PARENT_REVISION}:docs/verifier-trust-boundary.md")
        raise "V001 trust-boundary source was not introduced at the bound revision" if status.success?
      end

      def validate_repository_history!
        shallow, status = capture("git", "rev-parse", "--is-shallow-repository")
        raise "repository history state is unavailable" unless status.success?
        raise "direct IELR decision requires full Git history" unless shallow.strip == "false"
      end

      def validate_dossier_identity!
        source = File.binread(@dossier)
        raise "direct IELR decision dossier digest drift" unless Digest::SHA256.hexdigest(source) == DOSSIER_DIGEST

        bytes, status = capture("git", "show", "#{DOSSIER_REVISION}:#{DOSSIER_PATH}")
        raise "direct IELR decision dossier is unavailable at its publication revision" unless status.success?
        raise "direct IELR decision dossier publication digest drift" unless
          Digest::SHA256.hexdigest(bytes.b) == DOSSIER_DIGEST
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
