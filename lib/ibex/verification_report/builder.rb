# frozen_string_literal: true
# rbs_inline: enabled

require "digest"
require_relative "../ir"
require_relative "../verify"
require_relative "../version"

module Ibex
  module VerificationReport
    # Builds deterministic evidence from an Automaton IR verification run.
    class Builder
      # @rbs!
      #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[String, json_value]

      # @rbs (IR::Automaton automaton, table: TableArtifact::Document,
      #   source_records: Array[GenerationInput], table_path: String, strict: bool,
      #   max_states: Integer, max_items: Integer) -> void
      def initialize(automaton, table:, source_records:, table_path:, strict:, max_states:, max_items:)
        raise ArgumentError, "source_records must not be empty" if source_records.empty?
        if source_records.length > LogicalPath::MAX_INPUT_FILES
          raise ArgumentError, "verification reports support at most #{LogicalPath::MAX_INPUT_FILES} input files"
        end
        raise ArgumentError, "max_states must be positive" unless max_states.is_a?(Integer) && max_states.positive?
        raise ArgumentError, "max_items must be positive" unless max_items.is_a?(Integer) && max_items.positive?

        @automaton = CanonicalIR.new(automaton, source_records: source_records).build
        @table = table
        @source_records = source_records
        @table_path = LogicalPath.table(table_path)
        @strict = strict
        @max_states = max_states
        @max_items = max_items
      end

      # @rbs () -> String
      def render
        validate_table_identity!
        document = {
          "ibex_report" => IDENTIFIER,
          "schema_version" => SCHEMA_VERSION,
          "checker" => { "name" => "ibex.verify", "version" => Ibex::VERSION },
          "profile" => @strict ? "strict" : "default",
          "bounds" => bounds.transform_keys(&:to_s),
          "input" => input_identity,
          "ir" => ir_identity,
          "table" => table_identity,
          "outcome" => verification_outcome,
          "excluded_trust" => EXCLUDED_TRUST
        }
        document["evidence_digest"] = TableArtifact::Serializer.digest(document)
        TableArtifact::Serializer.dump(document)
      end

      private

      # @rbs () -> Hash[Symbol, Integer]
      def bounds
        { max_states: @max_states, max_items: @max_items }
      end

      # @rbs () -> Array[String]
      def requested_checks
        Verify::Verifier::DEFAULT_CHECKS + (@strict ? Verify::Verifier::STRICT_CHECKS : [])
      end

      # @rbs () -> Hash[String, json_value]
      def verification_outcome
        result = Verify::Verifier.new(
          @automaton, strict: @strict, max_states: @max_states, max_items: @max_items
        ).verify
        {
          "status" => result.valid? ? "pass" : "violations",
          "requested_checks" => requested_checks,
          "executed_checks" => result.checks,
          "violations" => result.violations.map { |violation| stringify_keys(violation.to_h) },
          "exhaustion" => nil
        }
      rescue Verify::BudgetExceeded => e
        {
          "status" => "exhausted",
          "requested_checks" => requested_checks,
          "executed_checks" => [],
          "violations" => [],
          "exhaustion" => { "kind" => "reference_collection_budget", "message" => e.message }
        }
      end

      # @rbs () -> Hash[String, json_value]
      def input_identity
        files = @source_records.map.with_index do |record, index|
          {
            "logical_path" => LogicalPath.input(record.path, index),
            "sha256" => prefixed_digest(record.sha256),
            "bytesize" => record.bytesize
          }
        end
        { "digest" => TableArtifact::Serializer.digest(files), "files" => files }
      end

      # @rbs () -> Hash[String, json_value]
      def ir_identity
        {
          "identity_scope" => IR_IDENTITY_SCOPE,
          "grammar" => {
            "schema_version" => @automaton.grammar.schema_version,
            "digest" => grammar_digest
          },
          "automaton" => {
            "schema_version" => @automaton.schema_version,
            "algorithm" => @automaton.algorithm,
            "digest" => automaton_digest
          }
        }
      end

      # @rbs () -> Hash[String, json_value]
      def table_identity
        {
          "logical_path" => @table_path,
          "artifact_type" => TableArtifact::ARTIFACT_TYPE,
          "schema_version" => TableArtifact::SCHEMA_VERSION,
          "representation" => @table.payload.dig("table_format", "representation"),
          "artifact_digest" => prefixed_digest(Digest::SHA256.hexdigest(@table.dump)),
          "payload_digest" => @table.identity.fetch("payload_digest")
        }
      end

      # @rbs () -> void
      def validate_table_identity!
        identity = @table.identity
        return if identity.fetch("grammar_digest") == grammar_digest &&
                  identity.fetch("automaton_digest") == automaton_digest

        raise ArgumentError, "table artifact does not match the supplied Automaton IR"
      end

      # @rbs () -> String
      def grammar_digest
        @grammar_digest ||= "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(@automaton.grammar))}"
      end

      # @rbs () -> String
      def automaton_digest
        @automaton_digest ||= "sha256:#{Digest::SHA256.hexdigest(IR::Serialize.dump(@automaton))}"
      end

      # @rbs (String digest) -> String
      def prefixed_digest(digest)
        digest.start_with?("sha256:") ? digest : "sha256:#{digest}"
      end

      # @rbs (Hash[Symbol, String] value) -> Hash[String, String]
      def stringify_keys(value)
        value.to_h { |key, child| [key.to_s, child] }
      end
    end
  end
end
