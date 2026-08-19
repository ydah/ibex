# frozen_string_literal: true

require "json"

module Ibex
  module Quality
    # Renders the public I001 record from its machine-readable dossier.
    class DirectIELRDocument
      PATH = "docs/records/ielr/direct-ielr-decision.md"

      def self.render(document)
        new(document).render
      end

      def self.write!(root: File.expand_path("../..", __dir__), dossier: nil)
        dossier ||= File.join(root, "tool/quality/evidence/direct-ielr-decision-v1.json")
        document = JSON.parse(File.binread(dossier))
        path = File.join(root, PATH)
        File.write(path, render(document))
        path
      end

      def initialize(document)
        @document = document
      end

      def render
        [frontmatter, overview, decision_rules, observations, triggers, legal, evidence].join
      end

      private

      def frontmatter
        <<~MARKDOWN
          ---
          title: Direct IELR decision dossier
          description: Evidence and release boundary for the experimental direct IELR construction strategy.
          ---

        MARKDOWN
      end

      def overview
        decision = @document.fetch("decision")
        <<~MARKDOWN
          # Direct IELR decision dossier

          I001 is **#{decision.fetch("value")}** for release promotion. An experimental direct IELR
          implementation may exist behind an explicit opt-in, but it is not authorized as
          the default or as a release-readiness claim; I002 remains
          blocked. This decision is a feature gate, not a claim that direct IELR has no
          future value.

          The machine record marks the decision `#{decision.fetch("status")}`, its basis
          `#{decision.fetch("basis")}`, and its review state `#{decision.fetch("review_state")}`.
          The reviewed evidence date is `#{decision.fetch("date")}` at revision
          `#{decision.fetch("revision")}`. It asserts no signer, consent, or personal
          decision attribution.

          The closed machine record is
          [`direct-ielr-decision-v1.json`](../../../tool/quality/evidence/direct-ielr-decision-v1.json),
          validated by
          [`direct-ielr-decision-v1.schema.json`](../../../schema/direct-ielr-decision-v1.schema.json).
          Run its evidence and policy gate with:

          ```sh
          bundle exec ruby -Ilib -r./tool/quality/direct_ielr_decision \\
            -e 'Ibex::Quality::DirectIELRDecision.new.verify!'
          ```

        MARKDOWN
      end

      def decision_rules
        policy = @document.fetch("policy")
        header = <<~MARKDOWN
          ## Decision rules

          A GO requires every GO condition. A single NO-GO condition is sufficient.
          The machine dossier is the canonical source for the conditions, statuses, and
          observed evidence rendered below.

        MARKDOWN
        header + condition_table("GO condition", policy.fetch("go_conditions")) + "\n" +
          condition_table("NO-GO condition", policy.fetch("no_go_conditions"))
      end

      def condition_table(label, conditions)
        rows = conditions.map do |condition|
          "| #{humanize(condition.fetch("id"))} | #{status(condition.fetch("status"))} | " \
            "#{condition.fetch("observed")} |"
        end
        "| #{label} | Status | Current evidence |\n| --- | --- | --- |\n#{rows.join("\n")}\n"
      end

      def observations
        values = @document.fetch("observations")
        workload = values.fetch("current_real_workload")
        scale = values.fetch("canonical_scale_cost")
        gaps = @document.fetch("verification_gaps")
        <<~MARKDOWN
          ## Bound observations and verification gaps

          Measured real grammars: **#{values.fetch("measured_real_grammars")}**.
          Verified public checkouts: **#{values.fetch("verified_public_checkouts")}**.
          Real IELR-required workloads: **#{values.fetch("real_ielr_required_workloads")}**.
          Semantically reviewed conflict removals: **#{values.fetch("semantically_reviewed_conflict_removals")}**.

          Current real workload `#{workload.fetch("id")}` records:

          | Measurement | Value |
          | --- | ---: |
          | LR(0) states | #{workload.fetch("lr0_states")} |
          | LR(0) items | #{workload.fetch("lr0_items")} |
          | Canonical states | #{workload.fetch("canonical_states")} |
          | Canonical items | #{workload.fetch("canonical_items")} |
          | Final states | #{workload.fetch("final_states")} |
          | Unresolved IELR conflicts | #{workload.fetch("unresolved_ielr_conflicts")} |

          Canonical scale status: `#{scale.fetch("status")}`.
          Current verified workflow: `#{scale.fetch("current_verified_workflow")}`.
          Scope: #{scale.fetch("scope")}

          V001 verification gaps remain explicit:

          #{gaps.map { |name, value| "- `#{name}`: `#{value}`" }.join("\n")}

        MARKDOWN
      end

      def triggers
        records = @document.fetch("reconsideration_triggers")
        <<~MARKDOWN
          ## Reconsideration gate

          Reconsideration requires all of the following new evidence:

          #{records.each_with_index.map { |record, index| "#{index + 1}. **#{humanize(record.fetch("id"))}:** #{record.fetch("required_evidence")}." }.join("\n")}

          State-count reduction without a real semantic or operational need does not
          reopen the gate.

        MARKDOWN
      end

      def legal
        provenance = @document.fetch("legal_provenance")
        <<~MARKDOWN
          ## Legal and implementation provenance

          Design lineage: `#{provenance.fetch("design_lineage")}`.
          Permitted design inputs: #{provenance.fetch("permitted_design_inputs").map { |value| "`#{value}`" }.join(", ")}.
          GPL implementation source used: `#{provenance.fetch("gpl_implementation_source_used")}`.
          GPL implementation source translated: `#{provenance.fetch("gpl_implementation_source_translated")}`.

          #{provenance.fetch("rule")}

        MARKDOWN
      end

      def evidence
        identity = @document.fetch("evidence_identity")
        sources = identity.fetch("sources")
        <<~MARKDOWN
          ## Evidence identity

          The machine dossier binds the evidence sources by path and SHA-256. It also binds:

          - H005 capture base revision `#{identity.fetch("profile_capture_base_revision")}`;
          - H005 bound-path digest `#{identity.fetch("profile_bound_paths_sha256")}`;
          - H005 implementation digest `#{identity.fetch("profile_implementation_sha256")}`;
          - V001 revision `#{identity.fetch("v001_revision")}`.

          | Source ID | Path | Role | SHA-256 |
          | --- | --- | --- | --- |
          #{sources.map { |source| "| `#{source.fetch("id")}` | `#{source.fetch("path")}` | #{source.fetch("role")} | `#{source.fetch("sha256")}` |" }.join("\n")}

          Aggregate source-list digest: `#{identity.fetch("sources_sha256")}`.

          Exact reviewed history is part of the evidence contract. A shallow checkout
          that omits the decision or V001 revision fails closed with an unavailable
          revision error. Jobs running this gate must fetch complete history; they must
          not silently weaken source verification to accommodate a depth-one checkout.
        MARKDOWN
      end

      def status(value)
        value.tr("_", " ").capitalize
      end

      def humanize(value)
        value.tr("-", " ").capitalize
      end
    end
  end
end
