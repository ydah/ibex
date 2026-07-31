# frozen_string_literal: true

require "json"
require_relative "../../lib/ibex"

module Ibex
  module Quality
    # Replays the first measured conflict-repair corpus and rejects drift.
    class Fix
      ROOT = File.expand_path("../..", __dir__)
      BASELINE = File.join(ROOT, "test/fixtures/fix/baseline.json")

      # @rbs () -> void
      def verify!
        actual = measure
        expected = JSON.parse(File.binread(BASELINE), symbolize_names: true)
        return if actual == expected

        warn JSON.pretty_generate(expected: expected, actual: actual)
        raise "fix baseline changed; review the measurement before updating #{BASELINE}"
      end

      # @rbs () -> Hash[Symbol, untyped]
      def measure
        outcomes = cases.map { |entry| measure_case(entry) }
        successes = outcomes.count { |entry| entry.fetch(:result) == "proposed" }
        {
          schema_version: 1,
          corpus: { total: outcomes.length, gallery_derived: 2, synthetic: outcomes.length - 2 },
          successes: successes,
          success_rate: format("%.1f%%", successes.fdiv(outcomes.length) * 100),
          cases: outcomes
        }
      end

      private

      # @rbs () -> Array[{ name: String, source: String, origin: String }]
      def cases
        gallery_cases + synthetic_cases
      end

      # @rbs () -> Array[{ name: String, source: String, origin: String }]
      def gallery_cases
        %w[calc sql-lite].map do |name|
          path = File.join(ROOT, "gallery", name, "grammar.y")
          source = File.binread(path).sub(/^preclow\n.*?^prechigh\n/m, "")
          { name: "gallery-#{name}-without-precedence", source: source, origin: "gallery-derived" }
        end
      end

      # @rbs () -> Array[{ name: String, source: String, origin: String }]
      def synthetic_cases
        shapes = %i[direct grouped primary]
        18.times.map do |index|
          shape = shapes.fetch(index % shapes.length)
          token = format("OP%02d", index + 1)
          {
            name: format("synthetic-%<shape>s-%<number>02d", shape: shape, number: index + 1),
            source: synthetic_source(shape, token, index + 1),
            origin: "synthetic"
          }
        end
      end

      # @rbs (Symbol shape, String token, Integer index) -> String
      def synthetic_source(shape, token, index)
        alternatives = case shape
                       when :direct then "expr: expr #{token} expr\n    | ATOM"
                       when :grouped then "expr: expr #{token} expr\n    | LP expr RP\n    | ATOM"
                       when :primary then "expr: expr #{token} expr\n    | primary\nprimary: ATOM"
                       else raise "unknown baseline shape #{shape}"
                       end
        <<~GRAMMAR
          class FixBaseline#{index}
          pragma extended
          expect 1
          rule
          start: expr
          #{alternatives}
          end
        GRAMMAR
      end

      # @rbs ({ name: String, source: String, origin: String } entry) ->
      #   { name: String, origin: String, result: String, proposals: Integer }
      def measure_case(entry)
        source = entry.fetch(:source)
        ast = Frontend::Parser.new(source, file: entry.fetch(:name), mode: :extended).parse
        grammar = Normalizer.new(ast, mode: :extended).normalize
        automaton = LALR::Builder.new(grammar).build
        report = Ibex::Fix.new(
          source,
          file: entry.fetch(:name), grammar: grammar, automaton: automaton,
          algorithm: :lalr, mode: :extended, equiv_samples: 10,
          equiv_max_tokens: 8, equiv_max_configurations: 50_000
        ).run
        proposals = report.fetch(:proposals)
        {
          name: entry.fetch(:name), origin: entry.fetch(:origin),
          result: proposals.empty? ? "no_safe_proposal" : "proposed",
          proposals: proposals.length
        }
      rescue Ibex::Fix::BudgetExceeded
        {
          name: entry.fetch(:name), origin: entry.fetch(:origin),
          result: "budget_exhausted", proposals: 0
        }
      end
    end
  end
end
