# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require_relative "error"
require_relative "generation_manifest"
require_relative "table_artifact"
require_relative "verification_report/logical_path"
require_relative "verification_report/canonical_ir"
require_relative "verification_report/builder"
require_relative "verification_report/validator"

module Ibex
  # A versioned, scoped report that binds bounded verification to input and
  # data-only parser table identities without claiming to verify opaque code.
  module VerificationReport
    IDENTIFIER = "scoped_verification" #: String
    SCHEMA_VERSION = 1 #: Integer
    IR_IDENTITY_SCOPE = "source-logical-v1" #: String
    DEFAULT_MAX_STATES = 100_000 #: Integer
    DEFAULT_MAX_ITEMS = 1_000_000 #: Integer
    EXCLUDED_TRUST = %w[
      source_to_ir table_semantic_derivation generated_wrapper semantic_actions lexer_actions
      runtime application_hooks grammar_unambiguity
    ].freeze #: Array[String]

    class ValidationError < Ibex::Error; end

    module_function

    # Rebuild the supplied Automaton IR with path-neutral source locations for one bundle.
    # @rbs (IR::Automaton automaton, source_records: Array[GenerationInput]) -> IR::Automaton
    def canonical_automaton(automaton, source_records:)
      CanonicalIR.new(automaton, source_records: source_records).build
    end

    # @rbs (IR::Automaton automaton, table: TableArtifact::Document,
    #   source_records: Array[GenerationInput], table_path: String, ?strict: bool,
    #   ?max_states: Integer, ?max_items: Integer) -> String
    def render(automaton, table:, source_records:, table_path:, strict: false,
               max_states: DEFAULT_MAX_STATES, max_items: DEFAULT_MAX_ITEMS)
      Builder.new(
        automaton, table: table, source_records: source_records, table_path: table_path,
                   strict: strict, max_states: max_states, max_items: max_items
      ).render
    end

    # Validate the closed report shape and its canonical evidence digest.
    # @rbs (String source) -> Hash[String, untyped]
    def validate(source)
      Validator.new.validate(source)
    end

    # Validate report, table, and manifest bytes as one non-cyclic bundle.
    # @rbs (manifest_source: String, report_source: String, table_source: String) -> Hash[String, untyped]
    def validate_bundle(manifest_source:, report_source:, table_source:)
      Validator.new.validate_bundle(
        manifest_source: manifest_source, report_source: report_source, table_source: table_source
      )
    end

    # Resolve the report and table through a manifest and validate every
    # published artifact before checking the cross-artifact identities.
    # @rbs (String manifest_path) -> Hash[String, untyped]
    def validate_bundle_file(manifest_path)
      Validator.new.validate_bundle_file(manifest_path)
    end
  end
end
