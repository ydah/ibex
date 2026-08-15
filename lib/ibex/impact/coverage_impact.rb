# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Impact
    # Selects separated runtime coverage reports for affected productions.
    class CoverageImpact
      attr_reader :status #: String
      attr_reader :reports #: Array[Hash[Symbol, Object?]]
      attr_reader :warnings #: Array[String]

      # @rbs (IR::Automaton automaton, Array[Integer], Array[[String, Coverage::Report]]) -> void
      def initialize(automaton, production_ids, reports)
        @automaton = automaton
        @production_ids = production_ids.sort
        @warnings = []
        @reports = select_reports(reports)
        @status = coverage_status(reports)
        freeze
      end

      # @rbs () -> Hash[Symbol, Object?]
      def to_h
        { status: @status, reports: @reports }
      end

      private

      # @rbs (Array[[String, Coverage::Report]]) -> Array[Hash[Symbol, Object?]]
      def select_reports(reports)
        selected = reports.filter_map do |path, report|
          unless report.grammar_digest == @automaton.grammar_digest
            @warnings << "#{path}: coverage grammar digest does not match the analysis input; report ignored"
            next
          end

          hits = report.production_hits.keys & @production_ids
          next if hits.empty?

          { path: path, productions: hits.sort }
        end
        selected.sort_by { |entry| entry.fetch(:path) }
      end

      # @rbs (Array[[String, Coverage::Report]]) -> String
      def coverage_status(reports)
        return "not_requested" if reports.empty?

        @reports.empty? ? "unmatched" : "matched"
      end
    end
  end
end
