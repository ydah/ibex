# frozen_string_literal: true

module Ibex
  module Quality
    # Reviewed canonical structures for jobs that carry ABI safety gates.
    module RuntimeABIReviewedWorkflow
      CHECKOUT = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
      RUBY_SETUP = "ruby/setup-ruby@95ef2b042f9d7a56d8268cba8559e2842e2ad01b"
      BUNDLE_ENV = { "BUNDLE_WITHOUT" => "types:docs:mutation:profile" }.freeze

      def self.commands(*values)
        values.join("\n").concat("\n")
      end

      STAGE_A_SAFETY = {
        "runs-on" => "ubuntu-latest", "name" => "Stage A safety net", "env" => BUNDLE_ENV,
        "steps" => [
          { "uses" => CHECKOUT, "with" => { "persist-credentials" => false } },
          {
            "name" => "Set up Ruby", "uses" => RUBY_SETUP,
            "with" => { "ruby-version" => "3.4", "bundler-cache" => true }
          },
          {
            "name" => "Verify deterministic safety gates",
            "run" => commands(
              "bundle exec rake test:matrix", "bundle exec rake test:zero_cost",
              "bundle exec rake test:reproducible", "bundle exec rake test:compat",
              "bundle exec rake test:ir_schema", "bundle exec rake test:no_exec",
              "bundle exec rake test:adversarial", "bundle exec rake gallery:build",
              "bundle exec rake gallery:conflicts", "bundle exec rake fuzz:short",
              "bundle exec rake fuzz:direct", "bundle exec rake fuzz:injection",
              "bundle exec rake deps:zero",
              "bundle exec rake network:zero"
            )
          },
          {
            "name" => "Run scheduled exhaustive gates", "if" => "github.event_name == 'schedule'",
            "env" => { "IBEX_ADVERSARIAL_FULL" => "1" },
            "run" => commands(
              "bundle exec rake test:matrix:full", "bundle exec rake test:adversarial",
              "bundle exec rake fuzz:long"
            )
          }
        ]
      }.freeze

      RUNTIME_ABI_ASSESSMENT = {
        "runs-on" => "ubuntu-latest", "name" => "Runtime ABI assessment",
        "permissions" => { "contents" => "read" }, "env" => BUNDLE_ENV,
        "steps" => [
          {
            "uses" => CHECKOUT,
            "with" => { "fetch-depth" => 0, "persist-credentials" => false }
          },
          {
            "name" => "Set up Ruby", "uses" => RUBY_SETUP,
            "with" => { "ruby-version" => "3.4", "bundler-cache" => true }
          },
          {
            "name" => "Enforce pull-request runtime ABI assessment",
            "if" => "github.event_name == 'pull_request'",
            "run" => "bundle exec rake quality:runtime_abi_pr"
          }
        ]
      }.freeze

      PROTECTED_JOBS = {
        "stage-a-safety" => STAGE_A_SAFETY,
        "runtime-abi-assessment" => RUNTIME_ABI_ASSESSMENT
      }.freeze
    end
  end
end
