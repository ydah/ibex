# frozen_string_literal: true

require "json"
require "json_schemer"
require_relative "../../benchmark/ielr"
require_relative "fuzz"

module Ibex
  module Quality
    # Runs the bounded direct-IELR regression probes without promoting I001.
    class DirectIELRRegression
      def initialize(root: File.expand_path("../..", __dir__), count: 100, wall_seconds: 5.0,
                     paths: nil, output: $stdout)
        @root = File.expand_path(root)
        @count = count
        @wall_seconds = wall_seconds
        @paths = paths
        @output = output
      end

      def verify!
        fuzz_report = Fuzz.new(root: @root, count: @count, ielr_strategy: :direct, output: @output).run
        benchmark_options = { root: @root, wall_seconds: @wall_seconds }
        benchmark_options[:paths] = @paths if @paths
        benchmark = IELRBenchmark.build(**benchmark_options)
        validate_benchmark_schema!(benchmark)
        repeat = IELRBenchmark.build(**benchmark_options)
        unless IELRBenchmark.deterministic_projection(benchmark) ==
               IELRBenchmark.deterministic_projection(repeat)
          raise "direct IELR benchmark structural projection drift"
        end

        validate_strategy_coverage!(benchmark)
        unless fuzz_report.all? { |report| report.fetch(:result) == "no_difference_within_bounds" }
          raise "direct IELR fuzz regression did not complete cleanly"
        end

        @output.puts "direct IELR bounded fuzz and direct/partition benchmark probes passed; I001 remains NO-GO"
        { fuzz: fuzz_report, benchmark: benchmark }
      end

      private

      def validate_benchmark_schema!(document)
        path = File.join(@root, "schema/ielr-benchmark-v1.schema.json")
        errors = JSONSchemer.schema(JSON.parse(File.binread(path))).validate(document).to_a
        raise "IELR benchmark violates schema: #{JSON.generate(errors)}" unless errors.empty?
      end

      def validate_strategy_coverage!(document)
        grouped = document.fetch("workloads").group_by { |item| item.fetch("id") }
        grouped.each do |id, workloads|
          strategies = workloads.map { |item| item.fetch("strategy") }.sort
          raise "IELR benchmark missing strategy pair for #{id}" unless strategies == %w[direct partition]
        end
      end
    end
  end
end
