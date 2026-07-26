# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Ibex
  module RaccMigration
    # One immutable migration compatibility observation.
    class Finding
      SEVERITIES = %i[error warning info].freeze #: Array[Symbol]

      attr_reader :code #: String
      attr_reader :severity #: Symbol
      attr_reader :message #: String
      attr_reader :location #: Frontend::Location?
      attr_reader :suggestion #: String

      # @rbs (code: String, severity: Symbol, message: String, location: Frontend::Location?,
      #   suggestion: String) -> void
      def initialize(code:, severity:, message:, location:, suggestion:)
        unless SEVERITIES.include?(severity)
          raise ArgumentError, "unknown migration finding severity #{severity.inspect}"
        end

        @code = code.dup.freeze
        @severity = severity
        @message = message.dup.freeze
        @location = location
        @suggestion = suggestion.dup.freeze
        freeze
      end

      # @rbs () -> Hash[String, untyped]
      def to_h
        {
          "code" => @code,
          "severity" => @severity.to_s,
          "message" => @message,
          "location" => @location&.to_h&.transform_keys(&:to_s),
          "suggestion" => @suggestion
        }
      end
    end

    # Versioned result of checking one grammar without executing its code.
    class Report
      SCHEMA_VERSION = 1 #: Integer

      attr_reader :file #: String
      attr_reader :class_name #: String?
      attr_reader :findings #: Array[Finding]

      # @rbs (file: String, class_name: String?, findings: Array[Finding]) -> void
      def initialize(file:, class_name:, findings:)
        @file = file.dup.freeze
        @class_name = class_name&.dup&.freeze
        @findings = findings.dup.freeze
        freeze
      end

      # @rbs () -> bool
      def compatible? = @findings.none? { |finding| finding.severity == :error }

      # @rbs () -> Hash[String, untyped]
      def to_h
        {
          "ibex_migration_check" => "racc",
          "schema_version" => SCHEMA_VERSION,
          "compatible" => compatible?,
          "file" => @file,
          "class_name" => @class_name,
          "findings" => @findings.map(&:to_h)
        }
      end

      # @rbs (*untyped) -> String
      def to_json(*) = JSON.pretty_generate(to_h)

      # @rbs () -> String
      def to_text
        return "#{@file}: compatible with the checked racc migration surface\n" if @findings.empty?

        lines = @findings.flat_map do |finding|
          prefix = finding.location ? finding.location.to_s : "#{@file}:1:1"
          [
            "#{prefix}: #{finding.severity}: #{finding.message} [#{finding.code}]",
            "  suggestion: #{finding.suggestion}"
          ]
        end
        "#{lines.join("\n")}\n"
      end
    end
  end
end
