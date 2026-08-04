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
      NORMAL_COMMANDS = %w[
        test:matrix test:zero_cost test:reproducible test:compat test:ir_schema test:no_exec
        test:adversarial gallery:build gallery:conflicts fuzz:short fuzz:injection deps:zero network:zero
      ].map { |task| "bundle exec rake #{task}" }.freeze
      ENFORCEMENT_COMMANDS = ["bundle exec rake quality:runtime_abi_pr"].freeze
      JOB_ENVIRONMENTS = {
        "stage-a-safety" => { "BUNDLE_WITHOUT" => "types:docs:mutation:profile" },
        "v1-contracts" => { "BUNDLE_WITHOUT" => "types:docs:mutation:profile" }
      }.freeze
      PR_CONDITION = "github.event_name == 'pull_request'"
      SCHEDULE_CONDITION = "github.event_name == 'schedule'"

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
        verify_triggers(workflow)
        raise "CI workflow must use the default safe shell" if workflow.key?("defaults")
        raise "CI workflow environment must be absent" if workflow.key?("env")

        safety_steps = safe_job_steps(workflow, "stage-a-safety")
        contract_steps = safe_job_steps(workflow, "v1-contracts")

        verify_normal_step(safety_steps)
        verify_scheduled_step(safety_steps)
        verify_enforcement_step(contract_steps)
      end

      def verify_normal_step(steps)
        step = named_step(steps, "Verify deterministic safety gates")
        verify_step_safety(step, expected_condition: nil)
        exact_keys!(step, %w[name run], "normal CI gate step")
        raise "normal gate commands are stale" unless run_commands(step) == NORMAL_COMMANDS
      end

      def verify_scheduled_step(steps)
        step = named_step(steps, "Run scheduled exhaustive gates")
        verify_step_safety(step, expected_condition: SCHEDULE_CONDITION)
        exact_keys!(step, %w[env if name run], "scheduled CI gate step")
        expected_env = { "IBEX_ADVERSARIAL_FULL" => "1" }
        raise "scheduled gate environment is stale" unless step.fetch("env") == expected_env

        expected = LONG_GATES.map { |task| "bundle exec rake #{task}" }
        raise "scheduled gate commands are stale" unless run_commands(step) == expected
      end

      def verify_enforcement_step(steps)
        step = named_step(steps, "Enforce pull-request runtime ABI assessment")
        verify_step_safety(step, expected_condition: PR_CONDITION)
        exact_keys!(step, %w[if name run], "pull-request ABI enforcement step")
        raise "pull-request ABI enforcement commands are stale" unless run_commands(step) == ENFORCEMENT_COMMANDS
      end

      def verify_triggers(workflow)
        triggers = workflow.fetch(true)
        expected = {
          "push" => { "branches" => ["main"] },
          "pull_request" => nil,
          "schedule" => [{ "cron" => "27 3 * * 1" }]
        }
        invalid = expected.reject do |trigger, value|
          triggers.is_a?(Hash) && triggers.key?(trigger) && triggers[trigger] == value
        end.keys
        raise "CI has missing or stale required triggers: #{invalid.join(', ')}" unless invalid.empty?
      end

      def safe_job_steps(workflow, name)
        job = workflow.dig("jobs", name)
        raise "#{name} job is missing" unless job.is_a?(Hash)

        forbidden = %w[if continue-on-error defaults] & job.keys
        raise "#{name} job has fail-open controls: #{forbidden.join(', ')}" unless forbidden.empty?
        raise "#{name} job environment is stale" unless job["env"] == JOB_ENVIRONMENTS.fetch(name)

        steps = job.fetch("steps")
        raise "#{name} steps are missing" unless steps.is_a?(Array)

        steps
      end

      def verify_step_safety(step, expected_condition:)
        forbidden = %w[continue-on-error shell] & step.keys
        raise "CI gate step has fail-open controls: #{forbidden.join(', ')}" unless forbidden.empty?

        if expected_condition
          raise "CI gate step condition is stale" unless step["if"] == expected_condition
        elsif step.key?("if")
          raise "normal CI gate must be unconditional"
        end
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
        %w[runtime_abi runtime_abi_pr].each do |task|
          raise "Rakefile is missing quality:#{task}" unless rakefile.match?(/task :#{task}\b/)
        end

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
