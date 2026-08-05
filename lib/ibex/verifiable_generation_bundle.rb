# frozen_string_literal: true
# rbs_inline: enabled

require_relative "artifact_set"
require_relative "generation_manifest"
require_relative "generation_transaction"
require_relative "table_artifact"
require_relative "verification_report"

module Ibex
  # Explicitly renders and publishes one manifest-bound verification bundle.
  class VerifiableGenerationBundle
    # rubocop:disable Metrics/ParameterLists -- persisted artifact paths and verification bounds are explicit inputs.
    # @rbs (IR::Automaton automaton, wrapper_path: String, wrapper_source: String,
    #   table_path: String, report_path: String, manifest_path: String,
    #   source_records: Array[GenerationInput], ?manifest_options: Hash[String, untyped],
    #   ?wrapper_mode: Integer?, ?representation: Symbol | String, ?cst_trivia: Symbol | String?,
    #   ?omit_action_call: bool?, ?strict: bool, ?max_states: Integer, ?max_items: Integer) -> void
    def initialize(automaton, wrapper_path:, wrapper_source:, table_path:, report_path:, manifest_path:,
                   source_records:, manifest_options: {}, wrapper_mode: nil, representation: :compact,
                   cst_trivia: nil, omit_action_call: nil, strict: false,
                   max_states: VerificationReport::DEFAULT_MAX_STATES,
                   max_items: VerificationReport::DEFAULT_MAX_ITEMS)
      @automaton = automaton
      @wrapper_path = wrapper_path
      @wrapper_source = wrapper_source
      @table_path = table_path
      VerificationReport::LogicalPath.table(table_path)
      if source_records.length > VerificationReport::LogicalPath::MAX_INPUT_FILES
        raise ArgumentError,
              "verification reports support at most #{VerificationReport::LogicalPath::MAX_INPUT_FILES} input files"
      end
      @report_path = report_path
      @manifest_path = manifest_path
      @source_records = source_records
      @manifest_options = manifest_options
      @wrapper_mode = wrapper_mode
      @representation = representation
      @cst_trivia = cst_trivia
      @omit_action_call = omit_action_call
      @strict = strict
      @max_states = max_states
      @max_items = max_items
    end
    # rubocop:enable Metrics/ParameterLists

    # Render table, wrapper, and report before the non-cyclic manifest marker.
    # @rbs () -> ArtifactSet
    def render
      canonical_automaton = VerificationReport.canonical_automaton(
        @automaton, source_records: @source_records
      )
      table = TableArtifact.build(
        canonical_automaton, representation: @representation, cst_trivia: @cst_trivia,
                             omit_action_call: @omit_action_call
      )
      artifacts = ArtifactSet.new
      artifacts.add(kind: :parser_table, path: @table_path, content: table.dump)
      artifacts.add(kind: :parser, path: @wrapper_path, content: @wrapper_source, mode: @wrapper_mode)
      report = VerificationReport.render(
        canonical_automaton, table: table, source_records: @source_records, table_path: @table_path,
                             strict: @strict, max_states: @max_states, max_items: @max_items
      )
      artifacts.add(kind: :verification_report, path: @report_path, content: report)
      manifest = GenerationManifest.render(
        artifacts, source_records: @source_records, options: @manifest_options
      )
      artifacts.add(kind: :manifest, path: @manifest_path, content: manifest)
      artifacts
    end

    # @rbs (?warning: ^(String) -> void, ?stability_check: ^() -> bool) -> ArtifactSet
    def publish(warning: ->(_message) {}, stability_check: -> { @source_records.all?(&:current?) })
      artifacts = render
      GenerationTransaction.new(
        artifacts, warning: warning, stability_check: stability_check, source_records: @source_records
      ).commit
      artifacts
    end

    # @rbs (String manifest_path) -> Hash[String, untyped]
    def self.validate_file(manifest_path)
      VerificationReport.validate_bundle_file(manifest_path)
    end
  end
end
