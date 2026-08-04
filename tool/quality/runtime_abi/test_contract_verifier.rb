# frozen_string_literal: true

require "yaml"
require_relative "document"
require_relative "reviewed_test_contract"

module Ibex
  module Quality
    # Cross-checks matrix arithmetic, interaction ownership, schedules, and goldens.
    class RuntimeABITestContractVerifier
      include RuntimeABIDocument

      LONG_GATES = %w[test:matrix:full test:adversarial fuzz:long].freeze

      def initialize(root:, contract:)
        @root = File.expand_path(root)
        @contract = contract
      end

      def verify!
        exact_keys!(@contract, %w[contract_version golden interactions matrix scheduled_long_gates],
                    "test interaction contract")
        raise "test interaction contract_version must be 1" unless @contract["contract_version"] == 1

        verify_matrix
        verify_interactions
        verify_schedule
        verify_golden
      end

      private

      def verify_matrix
        declared = YAML.safe_load_file(path("test/matrix.yml"), permitted_classes: [], aliases: false)
        matrix = @contract.fetch("matrix")
        exact_keys!(matrix, %w[axes expected_cases representative_cases roles], "test interaction matrix")
        expected_axes = RuntimeABIReviewedTestContract::AXES
        raise "documented matrix axes are stale or missing" unless matrix.fetch("axes") == expected_axes
        raise "test/matrix.yml axes are stale or invalid" unless declared.fetch("axes") == expected_axes

        product = matrix.fetch("axes").values.map(&:length).inject(1, :*)
        expected = matrix.fetch("expected_cases")
        raise "matrix expected_cases must be 96, got #{expected.inspect}" unless expected == 96
        raise "matrix product is #{product}, documented as #{expected}" unless product == expected
        raise "representative matrix must contain 12 cases" unless matrix.fetch("representative_cases") == 12
        unless declared.fetch("representative") == 12 && declared.fetch("full") == true
          raise "test/matrix.yml representative/full policy is stale"
        end

        roles = { "normal" => "representative", "scheduled" => "full", "promotion" => "full_review" }
        raise "matrix roles are stale" unless matrix.fetch("roles") == roles
      end

      def verify_interactions
        interactions = @contract.fetch("interactions")
        raise "interactions must be a non-empty list" unless interactions.is_a?(Array) && !interactions.empty?

        actual = interactions.to_h do |entry|
          exact_keys!(entry, %w[axes coverage id tests], "interaction #{entry['id']}")
          [entry.fetch("id"), entry.values_at("axes", "coverage", "tests")]
        end
        raise "interaction ids must be unique" unless actual.length == interactions.length
        unless actual == RuntimeABIReviewedTestContract::INTERACTIONS
          raise "interaction inventory, axes, coverage, or ownership is stale"
        end

        interactions.each { |entry| verify_test_paths(entry) }
      rescue KeyError => e
        raise "interaction is missing a required field: #{e.message}"
      end

      def verify_test_paths(entry)
        tests = entry.fetch("tests")
        unless tests.is_a?(Array) && !tests.empty? && tests.all?(String)
          raise "interaction #{entry.fetch('id')} must own tests"
        end

        missing = tests.reject { |test| File.file?(path(test)) }
        raise "interaction #{entry.fetch('id')} has missing tests: #{missing.join(', ')}" unless missing.empty?
      end

      def verify_schedule
        gates = @contract.fetch("scheduled_long_gates")
        raise "scheduled long gates are stale" unless gates == LONG_GATES

        workflow = YAML.safe_load_file(path(".github/workflows/main.yml"), permitted_classes: [], aliases: false)
        triggers = workflow.fetch(true)
        raise "CI schedule is missing" unless triggers.is_a?(Hash) && triggers.key?("schedule")

        steps = workflow.dig("jobs", "stage-a-safety", "steps")
        raise "stage-a-safety steps are missing" unless steps.is_a?(Array)

        verify_normal_step(steps)
        verify_scheduled_step(steps)
        verify_enforcement_step(workflow)
      end

      def verify_normal_step(steps)
        step = named_step(steps, "Verify deterministic safety gates")
        commands = run_commands(step)
        %w[test:matrix test:zero_cost].each do |task|
          raise "normal CI is missing bundle exec rake #{task}" unless commands.include?("bundle exec rake #{task}")
        end
      end

      def verify_scheduled_step(steps)
        step = named_step(steps, "Run scheduled exhaustive gates")
        expected_condition = "github.event_name == 'schedule'"
        raise "scheduled gate condition is stale" unless step.fetch("if") == expected_condition

        expected = LONG_GATES.map { |task| "bundle exec rake #{task}" }
        raise "scheduled gate commands are stale" unless run_commands(step) == expected
      end

      def verify_enforcement_step(workflow)
        steps = workflow.dig("jobs", "v1-contracts", "steps")
        raise "v1-contracts steps are missing" unless steps.is_a?(Array)

        step = named_step(steps, "Verify maturity, documentation, and localization contracts")
        command = "bundle exec rake quality:runtime_abi"
        raise "v1-contracts CI is missing #{command}" unless run_commands(step).include?(command)
      end

      def named_step(steps, name)
        matches = steps.select { |step| step["name"] == name }
        raise "CI must contain exactly one #{name.inspect} step" unless matches.length == 1

        matches.fetch(0)
      end

      def run_commands(step)
        run = step.fetch("run")
        raise "CI step run must be a String" unless run.is_a?(String)

        run.lines.map(&:strip).reject(&:empty?)
      end

      def verify_golden
        golden = @contract.fetch("golden")
        exact_keys!(golden, %w[digest_path policy sources task update_command], "golden contract")
        expected = {
          "task" => "test:zero_cost", "policy" => "feature_off_byte_identity",
          "digest_path" => "test/golden/digests.yml", "sources" => golden_sources,
          "update_command" => "bundle exec rake golden:update"
        }
        raise "golden zero-cost contract is stale" unless golden == expected
        raise "golden digest index is missing" unless File.file?(path(golden.fetch("digest_path")))

        rakefile = File.binread(path("Rakefile"))
        raise "Rakefile is missing quality:runtime_abi" unless rakefile.match?(/task :runtime_abi\b/)

        %w[test:zero_cost golden:update].each do |task|
          name = task.split(":").last
          raise "Rakefile is missing #{task}" unless rakefile.match?(/task :#{Regexp.escape(name)}\b/)
        end
      end

      def golden_sources
        source = File.binread(path("tool/quality/golden.rb"))
        match = source.match(/SOURCES = \[(.*?)\]\.freeze/m)
        raise "cannot find Golden::SOURCES" unless match

        match[1].scan(/"([^"]+)"/).flatten
      end

      def path(relative_path)
        File.join(@root, relative_path)
      end
    end
  end
end
