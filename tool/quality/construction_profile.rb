# frozen_string_literal: true

require "json"
require "json_schemer"
require_relative "../../lib/ibex"
require_relative "../profile/construction_profiler"
require_relative "construction_profile_integrity"

module Ibex
  module Quality
    # Validates the H005 evidence shape and deterministic structural projection.
    class ConstructionProfile
      def initialize(root: File.expand_path("../..", __dir__), evidence: nil, output: $stdout)
        @root = File.expand_path(root)
        @evidence = evidence || File.join(@root, "tool/profile/evidence/construction-profile-v1.json")
        @output = output
      end

      def verify!
        document = JSON.parse(File.binread(@evidence))
        validate_schema!(document)
        validate_integrity!(document)
        current = Profile::ConstructionReport.new(
          root: @root, wall_seconds: document.dig("measurement_policy", "wall_seconds_per_run")
        ).build
        validate_schema!(current)
        validate_integrity!(current)
        unless deterministic_projection(document) == deterministic_projection(current)
          raise "construction profile structural evidence drift; regenerate with tool/construction_profile.rb"
        end

        @output.puts "construction profile evidence matches deterministic structural observations"
        document
      end

      private

      def validate_schema!(document)
        path = File.join(@root, "schema/construction-profile-v1.schema.json")
        schema = JSONSchemer.schema(JSON.parse(File.binread(path)))
        errors = schema.validate(document).to_a
        raise "construction profile evidence violates schema: #{JSON.generate(errors)}" unless errors.empty?
      end

      def deterministic_projection(document)
        copy = Marshal.load(Marshal.dump(document))
        copy.delete("environment")
        copy.delete("provenance")
        copy.fetch("cohorts").each do |cohort|
          cohort.fetch("workloads").each do |workload|
            workload.fetch("runs").each do |run|
              run.dig("observations", "elapsed_seconds")["value"] = 0.0
            end
          end
        end
        copy
      end

      def validate_integrity!(document)
        ConstructionProfileProvenance.new(root: @root, document: document).verify!
        ConstructionProfileSemantics.new(document).verify!
      end
    end
  end
end
