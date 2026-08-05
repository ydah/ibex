# frozen_string_literal: true
# rbs_inline: enabled

require "digest"

module Ibex
  module VerificationReport
    # Validates a report and its cross-artifact manifest/table bindings.
    # rubocop:disable Metrics/ClassLength -- closed report and cross-artifact invariants form one validator contract.
    class Validator
      ROOT_KEYS = %w[
        ibex_report schema_version checker profile bounds input ir table outcome excluded_trust evidence_digest
      ].freeze #: Array[String]
      CHECKER_KEYS = %w[name version].freeze #: Array[String]
      BOUNDS_KEYS = %w[max_states max_items].freeze #: Array[String]
      INPUT_KEYS = %w[digest files].freeze #: Array[String]
      INPUT_FILE_KEYS = %w[logical_path sha256 bytesize].freeze #: Array[String]
      IR_KEYS = %w[grammar automaton].freeze #: Array[String]
      GRAMMAR_KEYS = %w[schema_version digest].freeze #: Array[String]
      AUTOMATON_KEYS = %w[schema_version algorithm digest].freeze #: Array[String]
      TABLE_KEYS = %w[
        logical_path artifact_type schema_version representation artifact_digest payload_digest
      ].freeze #: Array[String]
      OUTCOME_KEYS = %w[status requested_checks executed_checks violations exhaustion].freeze #: Array[String]
      VIOLATION_KEYS = %w[id location message].freeze #: Array[String]
      EXHAUSTION_KEYS = %w[kind message].freeze #: Array[String]
      DIGEST = /\Asha256:[0-9a-f]{64}\z/ #: Regexp
      ALGORITHMS = %w[slr lalr1 ielr1 lr1].freeze #: Array[String]

      # @rbs (String source) -> Hash[String, untyped]
      def validate(source)
        document = JSON.parse(source)
        validate_document(document)
        document
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
        raise ValidationError, "(verification-report):1:1: invalid report: #{e.message}"
      end

      # @rbs (manifest_source: String, report_source: String, table_source: String) -> Hash[String, untyped]
      def validate_bundle(manifest_source:, report_source:, table_source:)
        manifest = GenerationManifest.validate(manifest_source, verify_artifacts: false)
        report = validate(report_source)
        table = TableArtifact.load(table_source)
        report_entry = unique_artifact(manifest, "verification_report")
        table_entry = unique_artifact(manifest, "parser_table")
        unique_artifact(manifest, "parser")

        validate_manifest_bytes!(report_entry, report_source, "verification report")
        validate_manifest_bytes!(table_entry, table_source, "parser table")
        validate_inputs!(manifest, report)
        validate_table_binding!(report, table, table_entry)
        report
      rescue Ibex::Error => e
        raise e if e.is_a?(ValidationError)

        raise ValidationError, "(verification-bundle):1:1: #{e.message}"
      rescue KeyError, TypeError, ArgumentError => e
        raise ValidationError, "(verification-bundle):1:1: invalid bundle: #{e.message}"
      end

      # @rbs (String manifest_path) -> Hash[String, untyped]
      def validate_bundle_file(manifest_path)
        manifest_source = File.binread(manifest_path)
        manifest = GenerationManifest.validate(manifest_source, verify_artifacts: false)
        report_entry = unique_artifact(manifest, "verification_report")
        table_entry = unique_artifact(manifest, "parser_table")
        report_source = File.binread(report_entry.fetch("path"))
        table_source = File.binread(table_entry.fetch("path"))
        result = validate_bundle(
          manifest_source: manifest_source, report_source: report_source, table_source: table_source
        )
        GenerationManifest.validate(manifest_source)
        result
      rescue SystemCallError => e
        raise ValidationError, "#{manifest_path}:1:1: cannot read verification bundle: #{e.message}"
      end

      private

      # @rbs (untyped document) -> void
      def validate_document(document)
        object(document, ROOT_KEYS, "document")
        equal(document.fetch("ibex_report"), IDENTIFIER, "ibex_report")
        equal(document.fetch("schema_version"), SCHEMA_VERSION, "schema_version")
        validate_checker(document.fetch("checker"))
        profile = enum(document.fetch("profile"), %w[default strict], "profile")
        validate_bounds(document.fetch("bounds"))
        validate_input(document.fetch("input"))
        validate_ir(document.fetch("ir"))
        validate_table(document.fetch("table"))
        validate_outcome(document.fetch("outcome"), profile)
        equal(document.fetch("excluded_trust"), EXCLUDED_TRUST, "excluded_trust")
        digest(document.fetch("evidence_digest"), "evidence_digest")
        unsigned = document.except("evidence_digest")
        equal(document.fetch("evidence_digest"), TableArtifact::Serializer.digest(unsigned), "evidence_digest")
      end

      # @rbs (untyped value) -> void
      def validate_checker(value)
        checker = object(value, CHECKER_KEYS, "checker")
        equal(checker.fetch("name"), "ibex.verify", "checker.name")
        string(checker.fetch("version"), "checker.version")
      end

      # @rbs (untyped value) -> void
      def validate_bounds(value)
        bounds = object(value, BOUNDS_KEYS, "bounds")
        BOUNDS_KEYS.each { |key| positive_integer(bounds.fetch(key), "bounds.#{key}") }
      end

      # @rbs (untyped value) -> void
      def validate_input(value)
        input = object(value, INPUT_KEYS, "input")
        files = array(input.fetch("files"), "input.files")
        raise TypeError, "input.files must not be empty" if files.empty?

        files.each_with_index do |entry, index|
          file = object(entry, INPUT_FILE_KEYS, "input.files[#{index}]")
          path = logical_path(file.fetch("logical_path"), "input.files[#{index}].logical_path")
          expected_prefix = format("input/%04d/", index)
          raise TypeError, "input logical paths must use canonical indexes" unless path.start_with?(expected_prefix)

          digest(file.fetch("sha256"), "input.files[#{index}].sha256")
          nonnegative_integer(file.fetch("bytesize"), "input.files[#{index}].bytesize")
        end
        digest(input.fetch("digest"), "input.digest")
        equal(input.fetch("digest"), TableArtifact::Serializer.digest(files), "input.digest")
      end

      # @rbs (untyped value) -> void
      def validate_ir(value)
        ir = object(value, IR_KEYS, "ir")
        grammar = object(ir.fetch("grammar"), GRAMMAR_KEYS, "ir.grammar")
        automaton = object(ir.fetch("automaton"), AUTOMATON_KEYS, "ir.automaton")
        positive_integer(grammar.fetch("schema_version"), "ir.grammar.schema_version")
        positive_integer(automaton.fetch("schema_version"), "ir.automaton.schema_version")
        digest(grammar.fetch("digest"), "ir.grammar.digest")
        digest(automaton.fetch("digest"), "ir.automaton.digest")
        enum(automaton.fetch("algorithm"), ALGORITHMS, "ir.automaton.algorithm")
      end

      # @rbs (untyped value) -> void
      def validate_table(value)
        table = object(value, TABLE_KEYS, "table")
        path = logical_path(table.fetch("logical_path"), "table.logical_path")
        raise TypeError, "table.logical_path must use the table namespace" unless path.start_with?("table/")

        equal(table.fetch("artifact_type"), TableArtifact::ARTIFACT_TYPE, "table.artifact_type")
        equal(table.fetch("schema_version"), TableArtifact::SCHEMA_VERSION, "table.schema_version")
        enum(table.fetch("representation"), %w[plain compact], "table.representation")
        digest(table.fetch("artifact_digest"), "table.artifact_digest")
        digest(table.fetch("payload_digest"), "table.payload_digest")
      end

      # @rbs (untyped value, String profile) -> void
      def validate_outcome(value, profile)
        outcome = object(value, OUTCOME_KEYS, "outcome")
        status = enum(outcome.fetch("status"), %w[pass violations exhausted], "outcome.status")
        expected_checks = Verify::Verifier::DEFAULT_CHECKS +
                          (profile == "strict" ? Verify::Verifier::STRICT_CHECKS : [])
        requested = checks(outcome.fetch("requested_checks"), "outcome.requested_checks")
        executed = checks(outcome.fetch("executed_checks"), "outcome.executed_checks")
        equal(requested, expected_checks, "outcome.requested_checks")
        violations = validate_violations(outcome.fetch("violations"), requested)

        if status == "exhausted"
          equal(executed, [], "outcome.executed_checks")
          equal(violations, [], "outcome.violations")
          exhaustion = object(outcome.fetch("exhaustion"), EXHAUSTION_KEYS, "outcome.exhaustion")
          equal(exhaustion.fetch("kind"), "reference_collection_budget", "outcome.exhaustion.kind")
          string(exhaustion.fetch("message"), "outcome.exhaustion.message")
          return
        end

        equal(executed, requested, "outcome.executed_checks")
        equal(outcome.fetch("exhaustion"), nil, "outcome.exhaustion")
        if status == "pass"
          equal(violations, [], "outcome.violations")
        elsif violations.empty?
          raise TypeError, "outcome.violations must not be empty for violations status"
        end
      end

      # @rbs (untyped value, Array[String] requested) -> Array[untyped]
      def validate_violations(value, requested)
        violations = array(value, "outcome.violations")
        violations.each_with_index do |entry, index|
          violation = object(entry, VIOLATION_KEYS, "outcome.violations[#{index}]")
          enum(violation.fetch("id"), requested, "outcome.violations[#{index}].id")
          string(violation.fetch("location"), "outcome.violations[#{index}].location", allow_empty: true)
          string(violation.fetch("message"), "outcome.violations[#{index}].message")
        end
        violations
      end

      # @rbs (Hash[String, untyped] manifest, String kind) -> Hash[String, untyped]
      def unique_artifact(manifest, kind)
        entries = manifest.fetch("artifacts").select { |entry| entry.fetch("kind") == kind }
        raise TypeError, "manifest must list exactly one #{kind} artifact" unless entries.one?

        entries.fetch(0)
      end

      # @rbs (Hash[String, untyped] entry, String source, String label) -> void
      def validate_manifest_bytes!(entry, source, label)
        expected_digest = Digest::SHA256.hexdigest(source)
        raise TypeError, "#{label} manifest bytesize mismatch" unless entry.fetch("bytesize") == source.bytesize
        raise TypeError, "#{label} manifest digest mismatch" unless entry.fetch("sha256") == expected_digest
      end

      # @rbs (Hash[String, untyped] manifest, Hash[String, untyped] report) -> void
      def validate_inputs!(manifest, report)
        manifest_files = manifest.dig("input", "files").map.with_index do |entry, index|
          [
            "input/#{format('%04d', index)}/#{File.basename(entry.fetch('path'))}",
            "sha256:#{entry.fetch('sha256')}", entry.fetch("bytesize")
          ]
        end
        report_files = report.dig("input", "files").map do |entry|
          [entry.fetch("logical_path"), entry.fetch("sha256"), entry.fetch("bytesize")]
        end
        raise TypeError, "report input identity does not match manifest input" unless report_files == manifest_files
      end

      # @rbs (Hash[String, untyped] report, TableArtifact::Document table,
      #   Hash[String, untyped] table_entry) -> void
      def validate_table_binding!(report, table, table_entry)
        claim = report.fetch("table")
        expected_logical_path = "table/#{File.basename(table_entry.fetch('path'))}"
        equal(claim.fetch("logical_path"), expected_logical_path, "table.logical_path")
        equal(claim.fetch("artifact_digest"), "sha256:#{table_entry.fetch('sha256')}", "table.artifact_digest")
        equal(claim.fetch("payload_digest"), table.identity.fetch("payload_digest"), "table.payload_digest")
        equal(claim.fetch("representation"), table.payload.dig("table_format", "representation"),
              "table.representation")
        equal(report.dig("ir", "grammar", "digest"), table.identity.fetch("grammar_digest"),
              "ir.grammar.digest")
        equal(report.dig("ir", "automaton", "digest"), table.identity.fetch("automaton_digest"),
              "ir.automaton.digest")
      end

      # @rbs (untyped value, String path) -> Array[String]
      def checks(value, path)
        entries = array(value, path)
        entries.each { |entry| enum(entry, Verify::Verifier::DEFAULT_CHECKS + Verify::Verifier::STRICT_CHECKS, path) }
        raise TypeError, "#{path} must contain unique checks" unless entries.uniq == entries

        entries
      end

      # @rbs (untyped value, Array[String] keys, String path) -> Hash[String, untyped]
      def object(value, keys, path)
        raise TypeError, "#{path} must be an object" unless value.is_a?(Hash)
        raise TypeError, "#{path} keys must be strings" unless value.keys.all?(String)

        extras = value.keys - keys
        missing = keys - value.keys
        raise TypeError, "#{path} has unknown property #{extras.fetch(0)}" unless extras.empty?
        raise KeyError, "#{path} is missing #{missing.fetch(0)}" unless missing.empty?

        value
      end

      # @rbs (untyped value, String path) -> Array[untyped]
      def array(value, path)
        raise TypeError, "#{path} must be an array" unless value.is_a?(Array)

        value
      end

      # @rbs (untyped value, String path, ?allow_empty: bool) -> String
      def string(value, path, allow_empty: false)
        return value if value.is_a?(String) && (allow_empty || !value.empty?)

        raise TypeError, "#{path} must be #{allow_empty ? 'a string' : 'a non-empty string'}"
      end

      # @rbs (untyped value, String path) -> String
      def logical_path(value, path)
        value = string(value, path)
        components = value.split("/")
        absolute = value.start_with?("/") || value.match?(%r{\A[A-Za-z]:[\\/]})
        if absolute || components.include?("..") || value.include?("\\") || value.match?(/[[:cntrl:]]/)
          raise TypeError, "#{path} must be a logical relative path"
        end

        value
      end

      # @rbs (untyped value, String path) -> String
      def digest(value, path)
        return value if value.is_a?(String) && value.match?(DIGEST)

        raise TypeError, "#{path} must be a SHA-256 identity"
      end

      # @rbs (untyped value, String path) -> Integer
      def positive_integer(value, path)
        return value if value.is_a?(Integer) && value.positive?

        raise TypeError, "#{path} must be a positive integer"
      end

      # @rbs (untyped value, String path) -> Integer
      def nonnegative_integer(value, path)
        return value if value.is_a?(Integer) && value >= 0

        raise TypeError, "#{path} must be a non-negative integer"
      end

      # @rbs [T] (T value, Array[T] values, String path) -> T
      def enum(value, values, path)
        return value if values.include?(value)

        raise TypeError, "#{path} has an unsupported value"
      end

      # @rbs (untyped actual, untyped expected, String path) -> void
      def equal(actual, expected, path)
        return if actual == expected

        raise TypeError, "#{path} mismatch"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
