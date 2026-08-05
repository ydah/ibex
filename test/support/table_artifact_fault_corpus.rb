# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require "ibex/verifiable_generation_bundle"

module Ibex
  module TestSupport
    # Deterministic V004 mutations across the table, report, and manifest boundary.
    # rubocop:disable Metrics/ModuleLength -- the explicit mutation inventory is the auditable test contract.
    module TableArtifactFaultCorpus
      ROOT = File.expand_path("../..", __dir__)
      INVENTORY_PATH = File.join(ROOT, "test/fixtures/table_artifact/fault-injection-v1.json")
      TABLE_FIXTURE_PATH = File.join(ROOT, "test/fixtures/table_artifact/compact-v1.json")

      FAULT_METHODS = {
        "V004-GRAMMAR-DIGEST" => :fault_grammar_digest,
        "V004-SYMBOL-ID" => :fault_symbol_id,
        "V004-PRODUCTION-LENGTH" => :fault_production_length,
        "V004-PRODUCTION-LHS" => :fault_production_lhs,
        "V004-SHIFT-TARGET" => :fault_shift_target,
        "V004-GOTO-TARGET" => :fault_goto_target,
        "V004-ACCEPT-CELL" => :fault_accept_cell,
        "V004-DEFAULT-REDUCTION" => :fault_default_reduction,
        "V004-CONFLICT-RESOLVER" => :fault_conflict_resolver,
        "V004-COMPACT-OFFSET" => :fault_compact_offset,
        "V004-COMPACT-CHECK" => :fault_compact_check,
        "V004-COMPACT-VALUE" => :fault_compact_value,
        "V004-ENTRY-STATE" => :fault_entry_state,
        "V004-CST-METADATA-DIGEST" => :fault_cst_metadata_digest,
        "V004-TABLE-HASH" => :fault_table_hash,
        "V004-REPORT-HASH" => :fault_report_hash,
        "V004-REPORT-MANIFEST-HASH" => :fault_report_manifest_hash,
        "V004-MANIFEST-HASH" => :fault_manifest_hash,
        "V004-TRUNCATED-ARTIFACT" => :fault_truncated_artifact,
        "V004-DUPLICATE-ARTIFACT" => :fault_duplicate_artifact
      }.freeze

      ERROR_PATTERNS = {
        "V004-GRAMMAR-DIGEST" => /ir\.grammar\.digest mismatch/,
        "V004-SYMBOL-ID" => /symbols\[1\]\.id must be contiguous and ordered/,
        "V004-PRODUCTION-LENGTH" => /productions\[0\]\.rhs_length must match rhs/,
        "V004-PRODUCTION-LHS" => /productions\[0\]\.lhs must reference a nonterminal/,
        "V004-SHIFT-TARGET" => /actions\[[0-9]+\]\.code references a missing state/,
        "V004-GOTO-TARGET" => /gotos\[[0-9]+\]\.state references a missing state/,
        "V004-ACCEPT-CELL" => /accept is only valid for \$eof/,
        "V004-DEFAULT-REDUCTION" => /default_actions\[[0-9]+\] must be an error or reduction/,
        "V004-CONFLICT-RESOLVER" => /table\.artifact_digest mismatch/,
        "V004-COMPACT-OFFSET" => /must use the canonical minimal row-displacement layout/,
        "V004-COMPACT-CHECK" => /checks\[[0-9]+\] references a missing state/,
        "V004-COMPACT-VALUE" => /value and check occupancy must match/,
        "V004-ENTRY-STATE" => /entry_states\[0\]\.state references a missing state/,
        "V004-CST-METADATA-DIGEST" => /cst_metadata_digest does not match payload cst/,
        "V004-TABLE-HASH" => /payload_digest does not match the canonical payload/,
        "V004-REPORT-HASH" => /evidence_digest mismatch/,
        "V004-REPORT-MANIFEST-HASH" => /verification report manifest digest mismatch/,
        "V004-MANIFEST-HASH" => /parser table manifest digest mismatch/,
        "V004-TRUNCATED-ARTIFACT" => /invalid table artifact JSON/,
        "V004-DUPLICATE-ARTIFACT" => /exactly one parser_table artifact/
      }.freeze

      STRUCTURAL_SURVIVORS = %w[V004-GRAMMAR-DIGEST V004-CONFLICT-RESOLVER].freeze

      V004_SOURCE = <<~GRAMMAR
        class V004Parser
        pragma extended
        pragma cst
        token NUM PLUS
        expect 1
        rule
        start: expression @node Root(value)
        expression: expression PLUS expression { raise "V004 semantic action executed" }
                  | NUM { raise "V004 semantic action executed" }
        end
      GRAMMAR

      FaultResult = Struct.new(:error, :standalone_accepted, keyword_init: true)

      private

      def fault_inventory
        JSON.parse(File.binread(INVENTORY_PATH))
      end

      def exercise_table_artifact_fault(id)
        method_name = FAULT_METHODS.fetch(id)
        send(method_name)
      end

      def fault_symbol_id
        structural_fault do |document|
          document.dig("payload", "symbols", 1)["id"] = 2
        end
      end

      def fault_production_length
        structural_fault do |document|
          document.dig("payload", "productions", 0)["rhs_length"] += 1
        end
      end

      def fault_production_lhs
        structural_fault do |document|
          document.dig("payload", "productions", 0)["lhs"] = 0
        end
      end

      def fault_shift_target
        structural_fault do |document|
          payload = document.fetch("payload")
          codes = payload.dig("tables", "actions", "codes")
          index = codes.index { |code| code&.positive? } || raise("missing shift action")
          codes[index] = payload.fetch("state_count") + 1
        end
      end

      def fault_goto_target
        structural_fault do |document|
          payload = document.fetch("payload")
          values = payload.dig("tables", "gotos", "values")
          index = values.index { |state| !state.nil? } || raise("missing goto")
          values[index] = payload.fetch("state_count")
        end
      end

      def fault_accept_cell
        structural_fault do |document|
          actions = document.dig("payload", "tables", "actions")
          index = actions.fetch("checks").each_index.find do |candidate|
            row = actions.fetch("checks").fetch(candidate)
            row && (candidate - actions.fetch("offsets").fetch(row)).positive?
          end || raise("missing non-eof action")
          actions.fetch("codes")[index] = 0
        end
      end

      def fault_default_reduction
        structural_fault do |document|
          defaults = document.dig("payload", "tables", "default_actions")
          index = defaults.index { |code| !code.nil? } || raise("missing default reduction")
          defaults[index] = 1
        end
      end

      def fault_compact_offset
        structural_fault do |document|
          document.dig("payload", "tables", "actions", "offsets")[1] += 1
        end
      end

      def fault_compact_check
        structural_fault do |document|
          payload = document.fetch("payload")
          checks = payload.dig("tables", "actions", "checks")
          index = checks.index { |state| !state.nil? } || raise("missing compact check")
          checks[index] = payload.fetch("state_count")
        end
      end

      def fault_compact_value
        structural_fault do |document|
          actions = document.dig("payload", "tables", "actions")
          index = actions.fetch("checks").index { |state| !state.nil? } || raise("missing compact value")
          actions.fetch("codes")[index] = nil
        end
      end

      def fault_entry_state
        structural_fault do |document|
          payload = document.fetch("payload")
          payload.fetch("entry_states").fetch(0)["state"] = payload.fetch("state_count")
        end
      end

      def fault_cst_metadata_digest
        structural_fault do |document|
          document.dig("payload", "cst", "slots", 0)["node_name"] = "Changed"
        end
      end

      def fault_table_hash
        document = table_fixture
        document.dig("payload", "productions", 0)["rhs_length"] += 1
        FaultResult.new(error: capture_error { load_table(document) }, standalone_accepted: false)
      end

      def fault_truncated_artifact
        source = File.binread(TABLE_FIXTURE_PATH)
        error = capture_error { Ibex::TableArtifact.load(source.byteslice(0, source.bytesize / 2)) }
        FaultResult.new(error: error, standalone_accepted: false)
      end

      def fault_report_hash
        sources = bundle_sources
        report = JSON.parse(sources.fetch(:verification_report))
        report.fetch("checker")["version"] = "fault"
        source = Ibex::TableArtifact::Serializer.dump(report)
        error = capture_error { Ibex::VerificationReport.validate(source) }
        FaultResult.new(error: error, standalone_accepted: false)
      end

      def fault_report_manifest_hash
        sources = bundle_sources
        report = JSON.parse(sources.fetch(:verification_report))
        report.fetch("checker")["version"] = "fault"
        report_source = resign_report!(report)
        error = capture_error { validate_bundle(sources.merge(verification_report: report_source)) }
        FaultResult.new(error: error, standalone_accepted: false)
      end

      def fault_manifest_hash
        sources = bundle_sources
        manifest = JSON.parse(sources.fetch(:manifest))
        table_entry(manifest)["sha256"] = "0" * 64
        error = capture_error { validate_bundle(sources.merge(manifest: dump(manifest))) }
        FaultResult.new(error: error, standalone_accepted: false)
      end

      def fault_duplicate_artifact
        sources = bundle_sources
        manifest = JSON.parse(sources.fetch(:manifest))
        duplicate = deep_copy(table_entry(manifest))
        duplicate["path"] = "#{duplicate.fetch('path')}.duplicate"
        manifest.fetch("artifacts") << duplicate
        error = capture_error { validate_bundle(sources.merge(manifest: dump(manifest))) }
        FaultResult.new(error: error, standalone_accepted: false)
      end

      def fault_grammar_digest
        sources = bundle_sources
        table = JSON.parse(sources.fetch(:parser_table))
        changed_digest = "sha256:#{'0' * 64}"
        table.fetch("identity")["grammar_digest"] = changed_digest
        table.dig("payload", "source")["grammar_digest"] = changed_digest
        resign_table!(table)
        table_source = dump(table)

        report = JSON.parse(sources.fetch(:verification_report))
        bind_report_to_table!(report, table, table_source)
        report_source = resign_report!(report)
        manifest = JSON.parse(sources.fetch(:manifest))
        rebind_manifest!(manifest, "parser_table", table_source)
        rebind_manifest!(manifest, "verification_report", report_source)

        standalone = table_loads?(table_source)
        rebound = sources.merge(parser_table: table_source, verification_report: report_source,
                                manifest: dump(manifest))
        FaultResult.new(error: capture_error { validate_bundle(rebound) }, standalone_accepted: standalone)
      end

      def fault_conflict_resolver
        sources = bundle_sources
        table = JSON.parse(sources.fetch(:parser_table))
        actions = table.dig("payload", "tables", "actions")
        state_id, token_id, shift_id, production_id = conflict_coordinates
        index = actions.fetch("offsets").fetch(state_id) + token_id
        unless actions.fetch("checks").fetch(index) == state_id
          raise "conflict action is not stored in the selected row"
        end
        unless actions.fetch("codes").fetch(index) == shift_id + 1
          raise "conflict action does not match the selected shift alternative"
        end

        actions.fetch("codes")[index] = -2 - production_id
        resign_table!(table, refresh_cost: true)
        table_source = dump(table)
        manifest = JSON.parse(sources.fetch(:manifest))
        rebind_manifest!(manifest, "parser_table", table_source)

        standalone = table_loads?(table_source)
        rebound = sources.merge(parser_table: table_source, manifest: dump(manifest))
        FaultResult.new(error: capture_error { validate_bundle(rebound) }, standalone_accepted: standalone)
      end

      def conflict_coordinates
        state = bundle_automaton.states.find { |candidate| candidate.conflicts.any? } || raise("missing conflict")
        conflict = state.conflicts.find { |candidate| candidate.fetch(:type) == :shift_reduce } ||
                   raise("missing shift/reduce conflict")
        raise "fixture conflict must select shift before mutation" unless conflict.dig(:resolution, :chose) == :shift

        token_id = bundle_automaton.grammar.symbol(conflict.fetch(:symbol)).id
        [state.id, token_id, conflict.fetch(:shift_to), conflict.fetch(:reduce)]
      end

      def structural_fault
        document = table_fixture
        yield document
        resign_table!(document)
        FaultResult.new(error: capture_error { load_table(document) }, standalone_accepted: false)
      end

      def table_fixture
        JSON.parse(File.binread(TABLE_FIXTURE_PATH))
      end

      def load_table(document)
        Ibex::TableArtifact.load(dump(document))
      end

      def resign_table!(document, refresh_cost: false)
        payload = document.fetch("payload")
        document.fetch("identity")["payload_digest"] = Ibex::TableArtifact::Serializer.digest(payload)
        return unless refresh_cost

        document.fetch("cost")["canonical_payload_bytes"] = Ibex::TableArtifact::Serializer.compact(payload).bytesize
      end

      def resign_report!(document)
        document.delete("evidence_digest")
        document["evidence_digest"] = Ibex::TableArtifact::Serializer.digest(document)
        dump(document)
      end

      def bind_report_to_table!(report, table, table_source)
        claim = report.fetch("table")
        claim["artifact_digest"] = "sha256:#{Digest::SHA256.hexdigest(table_source)}"
        claim["payload_digest"] = table.dig("identity", "payload_digest")
      end

      def rebind_manifest!(manifest, kind, source)
        entry = manifest.fetch("artifacts").find { |candidate| candidate.fetch("kind") == kind } || raise
        entry["sha256"] = Digest::SHA256.hexdigest(source)
        entry["bytesize"] = source.bytesize
      end

      def table_entry(manifest)
        manifest.fetch("artifacts").find { |entry| entry.fetch("kind") == "parser_table" } || raise
      end

      def validate_bundle(sources)
        Ibex::VerificationReport.validate_bundle(
          manifest_source: sources.fetch(:manifest), report_source: sources.fetch(:verification_report),
          table_source: sources.fetch(:parser_table)
        )
      end

      def table_loads?(source)
        Ibex::TableArtifact.load(source)
        true
      end

      def capture_error
        yield
        nil
      rescue Ibex::Error => e
        e
      end

      def bundle_sources
        @bundle_sources ||= Dir.mktmpdir("ibex-v004") do |directory|
          render_bundle_sources(directory)
        end
      end

      def with_bundle_directory(directory)
        previous_sources = @bundle_sources
        previous_automaton = @bundle_automaton
        @bundle_sources = render_bundle_sources(directory)
        yield
      ensure
        @bundle_sources = previous_sources
        @bundle_automaton = previous_automaton
      end

      def render_bundle_sources(directory)
        source_path = File.join(directory, "grammar.y")
        File.binwrite(source_path, V004_SOURCE)
        @bundle_automaton = build_bundle_automaton(source_path)
        records = [Ibex::GenerationInput.new(source_path, V004_SOURCE)]
        bundle = Ibex::VerifiableGenerationBundle.new(
          @bundle_automaton,
          wrapper_path: File.join(directory, "parser.rb"),
          wrapper_source: Ibex::Codegen::Ruby.new(@bundle_automaton).generate,
          table_path: File.join(directory, "parser.tables.ibex.json"),
          report_path: File.join(directory, "parser.verification.ibex.json"),
          manifest_path: File.join(directory, "manifest.ibex.json"),
          source_records: records,
          manifest_options: { "table" => "compact" },
          representation: :compact,
          cst_trivia: :leading
        )
        bundle.render.to_h { |artifact| [artifact.kind, artifact.content] }.freeze
      end

      def bundle_automaton
        bundle_sources
        @bundle_automaton
      end

      def build_bundle_automaton(path)
        ast = Ibex::Frontend::Parser.new(V004_SOURCE, file: path, mode: :extended).parse
        grammar = Ibex::Normalizer.new(ast, mode: :extended).normalize
        Ibex::LALR::Builder.new(grammar).build
      end

      def deep_copy(value)
        JSON.parse(JSON.generate(value))
      end

      def dump(value)
        Ibex::TableArtifact::Serializer.dump(value)
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
