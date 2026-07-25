# frozen_string_literal: true

module Ibex
  module Frontend
    # An immutable machine-readable frontend error.
    class Diagnostic
      attr_reader :code #: String
      attr_reader :phase #: Symbol
      attr_reader :message #: String
      attr_reader :location #: Location
      attr_reader :span #: SourceSpan?
      attr_reader :expected #: Array[String]
      attr_reader :received #: String?

      # @rbs (code: String, phase: Symbol, message: String, location: Location, ?span: SourceSpan?,
      #   ?expected: Array[String], ?received: String?, ?rendered: String?) -> void
      def initialize(code:, phase:, message:, location:, span: nil, expected: [], received: nil, rendered: nil)
        @code = code.dup.freeze
        @phase = phase
        @message = message.dup.freeze
        @location = Location.new(
          file: location.file.dup.freeze, line: location.line, column: location.column
        ).freeze
        @span = span
        @expected = expected.map { |value| value.dup.freeze }.freeze
        @received = received&.dup&.freeze
        @rendered = (rendered || "#{location}: #{message}").dup.freeze
        freeze
      end

      # @rbs () -> String
      def severity
        "error"
      end

      # @rbs () -> String
      def to_s
        @rendered
      end

      # @rbs () -> Hash[Symbol, untyped]
      def to_h
        {
          code: code,
          severity: severity,
          phase: phase.to_s,
          message: message,
          location: location.to_h,
          span: span&.to_h,
          expected: expected,
          received: received
        }
      end
    end

    # Immutable output from a diagnostic parse.
    class ParseResult
      attr_reader :diagnostics #: Array[Diagnostic]
      attr_reader :ast #: AST::Root?
      attr_reader :document #: SourceDocument?

      # @rbs (diagnostics: Array[Diagnostic], ast: AST::Root?, document: SourceDocument?) -> void
      def initialize(diagnostics:, ast:, document:)
        @diagnostics = diagnostics.dup.freeze
        @ast = ast
        @document = document
        freeze
      end

      # @rbs () -> bool
      def success?
        diagnostics.empty? && !ast.nil?
      end

      # @rbs () -> bool
      def partial?
        diagnostics.any? && !ast.nil?
      end
    end
  end
end
