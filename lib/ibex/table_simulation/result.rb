# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Ibex
  module TableSimulation
    # Final immutable simulation document.
    class Result
      # @rbs!
      #   type step_document = Hash[String, Step::document_value]
      #   type document_value = String | Integer | Array[String] | Array[step_document]

      IDENTIFIER = "table-simulation" #: String
      SCHEMA_VERSION = 1 #: Integer

      attr_reader :grammar_digest #: String
      attr_reader :algorithm #: String
      attr_reader :tokens #: Array[String]
      attr_reader :status #: Symbol
      attr_reader :steps #: Array[Step]

      # @rbs (grammar_digest: String, algorithm: String, tokens: Array[String], status: Symbol,
      #   steps: Array[Step]) -> void
      def initialize(grammar_digest:, algorithm:, tokens:, status:, steps:)
        raise ArgumentError, "simulation status must be accepted or error" unless %i[accepted error].include?(status)

        @grammar_digest = grammar_digest.dup.freeze
        @algorithm = algorithm.dup.freeze
        @tokens = tokens.map { |token| token.dup.freeze }.freeze
        @status = status
        @steps = steps.dup.freeze
        freeze
      end

      # @rbs () -> Hash[String, document_value]
      def to_h
        {
          "ibex_table_simulation" => IDENTIFIER,
          "schema_version" => SCHEMA_VERSION,
          "grammar_digest" => @grammar_digest,
          "algorithm" => @algorithm,
          "tokens" => @tokens,
          "status" => @status.to_s,
          "steps" => @steps.map(&:to_h)
        }
      end

      # @rbs (*Object?) -> String
      def to_json(*)
        "#{JSON.pretty_generate(to_h)}\n"
      end
    end
  end
end
