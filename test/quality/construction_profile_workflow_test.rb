# frozen_string_literal: true

require_relative "../test_helper"
require "yaml"

class ConstructionProfileWorkflowTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  WORKFLOW = File.join(ROOT, ".github/workflows/main.yml")
  CHECKOUT = %r{\Aactions/checkout@}
  HISTORY_DEPENDENT_COMMANDS = [
    "bundle exec rake",
    "bundle exec rake test",
    "bundle exec rake quality:construction_profile"
  ].freeze

  def test_jobs_running_construction_profile_checks_fetch_complete_history
    checked_jobs = []

    workflow.fetch("jobs").each do |job_name, job|
      checkout_depth = nil

      job.fetch("steps", []).each do |step|
        checkout_depth = step.dig("with", "fetch-depth") if step.fetch("uses", "").match?(CHECKOUT)
        next unless history_dependent_run?(step["run"])

        checked_jobs << job_name
        assert_equal 0, checkout_depth,
                     "#{job_name} must fetch complete history before construction profile checks"
      end
    end

    %w[build frozen-strings].each do |job_name|
      assert_includes checked_jobs, job_name
    end
  end

  private

  def workflow
    YAML.safe_load_file(WORKFLOW, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def history_dependent_run?(run)
    return false unless run

    run.lines.any? do |line|
      HISTORY_DEPENDENT_COMMANDS.include?(line.strip)
    end
  end
end
